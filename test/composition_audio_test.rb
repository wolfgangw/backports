# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'stringio'
require 'rbconfig'
require 'open3'
require_relative 'support/media_fixture'
require_relative 'support/inspection_fixture'
require_relative '../lib/dcp_inspect/inspection/composition_audio'

class CompositionAudioTest < Minitest::Test
  include MediaFixture
  include InspectionFixture
  Audio = DcpInspect::Inspection::CompositionAudio
  Layout = DcpInspect::Inspection::PcmLayout

  def segment(path, entry, duration, channels: 2, samples: 2000)
    { path: path, entry: entry, duration: duration, channels: channels, samples_per_frame: samples, sample_rate: 48_000 }
  end
  def write_pcm(path, frames)
    File.binwrite(path, mxf(*frames.map { |bytes| klv(Audio::PCM + "\x01".b, bytes) }))
  end
  def stereo_tone(amplitude)
    2000.times.map do |i|
      sample = (Math.sin(2 * Math::PI * i / 40) * amplitude * 8_388_607).round
      bytes = [sample & 255, (sample >> 8) & 255, (sample >> 16) & 255].pack('C3')
      bytes * 2
    end.join
  end
  def runtime
    Runtime.new(options: DcpInspect::CLI::Options.parse(['--nh', '--na']), stdout: StringIO.new)
  end

  def test_selected_windows_preserve_order_reuse_and_sample_count
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'audio.mxf')
      frames = %w[a b c d].map { |letter| letter * 12 }
      write_pcm(path, frames)
      segments = [segment(path, 3, 1, samples: 2), segment(path, 1, 2, samples: 2)]
      assert_equal frames[3] + frames[1] + frames[2], Audio.chunks(segments).to_a.join
      assert_raises(Audio::Error) { Audio.chunks([segment(path, 3, 2, samples: 2)]).to_a }
    end
  end

  def test_programme_mapping_excludes_assistance_and_sync
    layout = Layout.resolve({ 'ChannelCount' => '14', 'ChannelFormat' => '4' })
    assert_equal [0, 1, 2, 3, 4, 5, 10, 11], layout[:map].map(&:last)
    assert_equal [6, 7, 8, 9, 12, 13], layout[:excluded_channels]
    assert_includes layout[:source], 'inferred'
    assert Layout.resolve({ 'ChannelCount' => '12', 'ChannelFormat' => '0' })[:skipped]
  end

  def test_mca_uses_dictionary_ids_and_group_links_not_symbol_names
    group_id = '00000000-0000-4000-8000-000000000001'
    header = "060e2b34.02530101.0d010101.01016c00  len: 100 (SoundfieldGroupLabelSubDescriptor)\n MCALabelDictionaryID = 060e2b34.0401010d.03020205.00000000\n MCALinkID = #{group_id}\n"
    header += "060e2b34.02530101.0d010101.01016b00  len: 100 (AudioChannelLabelSubDescriptor)\n MCALabelDictionaryID = 060e2b34.0401010d.03020103.00000000\n MCAChannelID = 1\n MCATagSymbol = chHI\n SoundfieldGroupLinkID = #{group_id}\n"
    meta = { 'ChannelCount' => '1', 'ChannelFormat' => '6' }
    assert_equal [['FC', 0]], Layout.resolve(meta, header)[:map]
    assert Layout.resolve(meta, header.sub("SoundfieldGroupLinkID = #{group_id}", 'SoundfieldGroupLinkID = wrong'))[:skipped]
  end

  def test_one_gated_measurement_matches_continuous_pcm_oracle
    skip 'ffmpeg unavailable' unless system('ffmpeg', '-version', out: File::NULL, err: File::NULL)
    Dir.mktmpdir do |dir|
      a, b = File.join(dir, 'quiet.mxf'), File.join(dir, 'loud.mxf')
      quiet, loud = stereo_tone(0.001), stereo_tone(0.1)
      write_pcm(a, [quiet] * 96)
      write_pcm(b, [loud] * 96)
      layout = Layout.resolve({ 'ChannelCount' => '2', 'ChannelFormat' => '0' })
      measured = runtime.parse_ffmpeg_audio_analysis(Audio.measure([segment(a, 0, 96), segment(b, 0, 96)], layout))
      _out, stderr, status = Open3.capture3('ffmpeg', '-hide_banner', '-nostats', '-f', 's24le', '-ar', '48000', '-ac', '2', '-i', 'pipe:0', '-af', 'ebur128=peak=true,astats=metadata=0:reset=0', '-f', 'null', '-', stdin_data: quiet * 96 + loud * 96, binmode: true)
      assert status.success?, stderr
      oracle = runtime.parse_ffmpeg_audio_analysis(stderr)
      assert_in_delta oracle[:integrated_lufs], measured[:integrated_lufs], 0.01
      assert_in_delta oracle[:lra_lu], measured[:lra_lu], 0.01
      # The quiet reel falls below the relative gate; averaging its LUFS with
      # the loud reel would produce a markedly lower and incorrect result.
      assert_operator measured[:integrated_lufs], :>, -25
      assert_equal 'MEASURED', measured[:status]
    end
  end

  def test_consumer_failure_and_interruption_reap_process_and_close_mxf
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'audio.mxf')
      write_pcm(path, [stereo_tone(0.1)] * 48)
      layout = Layout.resolve({ 'ChannelCount' => '2', 'ChannelFormat' => '0' })
      assert_raises(Audio::Error) do
        Audio.measure([segment(path, 0, 48)], layout, command: [RbConfig.ruby, '-e', 'warn "consumer failed"; exit 3'])
      end
      record = File.join(dir, 'pid')
      command = [RbConfig.ruby, '-e', 'File.write(ARGV[0], Process.pid); loop { STDIN.readpartial(4096) }', record]
      assert_raises(Interrupt) do
        Audio.measure([segment(path, 0, 48)], layout, command: command) do |written, _total|
          raise Interrupt if written > 20_000 && File.exist?(record)
        end
      end
      pid = File.read(record).to_i
      assert_raises(Errno::ESRCH) { Process.kill(0, pid) }
      leaked = Dir['/proc/self/fd/*'].filter_map { |fd| File.readlink(fd) rescue nil }.include?(path)
      refute leaked, 'MXF remained open after interruption'
    end
  end

  def test_native_pcm_mca_and_composition_exclude_hi
    skip 'native audio tools unavailable' unless %w[ffmpeg asdcp-wrap].all? { |tool| system(tool, tool == 'ffmpeg' ? '-version' : '-V', out: File::NULL, err: File::NULL) }
    Dir.mktmpdir do |dir|
      wav, mxf_path = File.join(dir, 'audio.wav'), File.join(dir, 'audio.mxf')
      signal = 'aevalsrc=0.01*sin(2*PI*1000*t)|0|0|0|0|0|0.5*sin(2*PI*500*t)|0:s=48000:d=2'
      _out, diagnostic, status = Open3.capture3('ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', signal, '-c:a', 'pcm_s24le', wav)
      assert status.success?, diagnostic
      _out, diagnostic, status = Open3.capture3('asdcp-wrap', '-L', '-a', fixture_uuid(5), '-m', '51(L,R,C,LFE,Ls,Rs),HI,VIN', wav, mxf_path)
      assert status.success?, diagnostic
      inspector = runtime
      inspector.instance_variable_set(:@package_dir, dir)
      references = [12, 0].each_with_index.map do |entry, index|
        { kind: 'MainSound', id: 'audio', reel_no: index + 1, entry_point: entry, duration: 12, edit_rate_ratio: '24/1' }
      end
      result = inspector.composition_audio_measurement(references, 2, { 'audio' => 'audio.mxf' }, true)
      refute result[:skipped], result.inspect
      refute result[:error], result.inspect
      assert_equal 48_000, result[:samples]
      assert_equal [6, 7], result[:channel_mapping][:excluded_channels]
      assert_equal 'MCA dictionary IDs and soundfield links', result[:channel_mapping][:source]
      assert_operator result[:integrated_lufs], :<, -35

      native_meta = Runtime::MxfTools.mxf_inspect(mxf_path)
      with_inspection_fixture do
        FileUtils.cp(mxf_path, File.join(@directory, 'sound.mxf'))
        @metadata['sound.mxf'] = native_meta
        @metadata['picture.mxf']['ContainerDuration'] = '48'
        write_cpl(reels: [reference('MainPicture', 4, duration: '48', intrinsic: '48') + reference('MainSound', 5, duration: '48', intrinsic: '48')])
        write_package
        inspected = inspect_fixture(audio: true)
        assert_empty inspected[:errors]
        check = inspected[:inspection_run].compositions.values.first.checks.find { |item| item.kind == :composition_audio }
        assert_equal :info, check.status
        assert_equal 96_000, check.details[:samples]
        assert_operator check.details[:integrated_lufs], :<, -35
      end
    end
  end
end
