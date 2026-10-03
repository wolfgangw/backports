# frozen_string_literal: true
require 'minitest/autorun'
require 'open3'
require_relative 'support/inspection_fixture'

class SubtitleInspectionTest < Minitest::Test
  include InspectionFixture

  def runtime(schema: false)
    flags = ['--nh', '--na']
    flags << '--no-schema' unless schema
    instance = Runtime.new(options: DcpInspect::CLI::Options.parse(flags), stdout: StringIO.new)
    instance.instance_variable_set(:@package_dir, @directory)
    instance
  end

  def test_interop_resources_use_exact_relative_paths_and_pkl_membership
    with_inspection_fixture do
      FileUtils.mkdir_p(File.join(@directory, 'subs'))
      path = File.join(@directory, 'subs', 'subtitle.xml')
      png = "\x89PNG\r\n\x1a\n".b + [13].pack('N') + 'IHDR' + [1920, 80].pack('NN')
      File.binwrite(File.join(@directory, 'subs', 'line[1].png'), png)
      File.write(File.join(@directory, 'subs', 'line1.png'), 'decoy')
      xml = Nokogiri::XML("<DCSubtitle><SubtitleID>#{fixture_uuid(6)}</SubtitleID><ReelNumber>1</ReelNumber><Language>en</Language><Subtitle SpotNumber='1' TimeIn='00:00:01:000' TimeOut='00:00:02:000'><Image>line%5B1%5D.png</Image></Subtitle></DCSubtitle>")
      result = runtime.inspect_subtitle_document(xml, path, { 'image' => 'subs/line[1].png' }, {})
      assert_empty result[:findings]
      result = runtime.inspect_subtitle_document(xml, path, { 'decoy' => 'subs/line1.png' }, {})
      assert result[:findings].any? { |f| f[:code] == 'timed-text.resource.missing' }
    end
  end

  def test_encrypted_subtitles_are_explicitly_unchecked
    with_inspection_fixture do
      result = runtime.inspect_embedded_subtitle('nonexistent.mxf', { 'EncryptedEssence' => 'Yes' }, {}, {})
      assert_equal :hint, result[:findings].first[:severity]
      assert_equal 'timed-text.encrypted.unchecked', result[:findings].first[:code]
    end
  end

  def test_native_smpte_extraction_resources_identity_and_schema
    skip 'asdcp-wrap unavailable' unless system('asdcp-wrap', '-V', out: File::NULL, err: File::NULL)
    with_inspection_fixture do
      resource_id = fixture_uuid(7)
      png = [ '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000b49444154789c636000020000050001a5f645400000000049454e44ae426082' ].pack('H*')
      File.binwrite(File.join(@directory, resource_id), png)
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <SubtitleReel xmlns="http://www.smpte-ra.org/schemas/428-7/2010/DCST">
          <Id>urn:uuid:#{fixture_uuid(6)}</Id><ContentTitleText>Extraction test</ContentTitleText>
          <IssueDate>2026-10-03T00:00:00Z</IssueDate><ReelNumber>1</ReelNumber><Language>en</Language>
          <EditRate>24 1</EditRate><TimeCodeRate>24</TimeCodeRate><StartTime>00:00:00:00</StartTime>
          <SubtitleList><Subtitle SpotNumber="1" TimeIn="00:00:01:00" TimeOut="00:00:10:00">
            <Image Halign="center" Hposition="0" Valign="bottom" Vposition="10">urn:uuid:#{resource_id}</Image>
          </Subtitle></SubtitleList>
        </SubtitleReel>
      XML
      source, mxf = File.join(@directory, 'source.xml'), File.join(@directory, 'subtitle.mxf')
      File.write(source, xml)
      _stdout, stderr, status = Open3.capture3('asdcp-wrap', '-L', '-a', fixture_uuid(8), source, mxf)
      assert status.success?, stderr
      meta = Runtime::MxfTools.mxf_inspect(mxf)
      context = { document_id: meta['AssetID'], descriptor_rate: Rational(24), intrinsic: 240,
        edit_rate: Rational(24), kind: 'MainSubtitle', declared_resources: { resource_id => 'image/png' } }
      result = runtime(schema: true).inspect_embedded_subtitle(mxf, meta, {}, context)
      assert_empty result[:findings]
      assert_equal 1, result[:summary][:resources].size
      assert_equal '10/1', result[:summary][:last_time_out]
      assert_equal fixture_uuid(6), meta['AssetID']
      refute_equal meta['AssetUUID'], meta['AssetID']
      bad = runtime.inspect_embedded_subtitle(mxf, meta, {}, context.merge(document_id: fixture_uuid(99)))
      assert bad[:findings].any? { |f| f[:code] == 'timed-text.id.mismatch' }
      undeclared = runtime.inspect_embedded_subtitle(mxf, meta, {}, context.merge(declared_resources: {}))
      assert undeclared[:findings].any? { |f| f[:code] == 'timed-text.resource.not-in-descriptor' }

      @metadata['subtitle.mxf'] = meta
      @metadata.each_value { |asset| asset['Label Set Type'] = 'SMPTE' }
      write_cpl(namespace: V::Smpte_cpl, reels: [reference('MainPicture', 4) + reference('MainSound', 5) + reference('MainSubtitle', 8)])
      write_package(assets: [[3, 'CPL.xml', 'text/xml'], [4, 'picture.mxf', 'application/mxf'], [5, 'sound.mxf', 'application/mxf'], [8, 'subtitle.mxf', 'application/mxf']])
      pkl_path = File.join(@directory, 'PKL.xml')
      File.write(pkl_path, File.read(pkl_path).sub(V::Interop_pkl, V::Smpte_pkl))
      am_path = File.join(@directory, 'ASSETMAP')
      File.write(am_path, File.read(am_path).sub(V::Interop_am, V::Smpte_am).sub('<PackingList/>', '<PackingList>true</PackingList>'))
      File.rename(am_path, am_path + '.xml')
      inspection = inspect_fixture
      assert_empty inspection[:errors]
      composition = inspection[:inspection_run].compositions.values.first
      assert composition.checks.any? { |check| check.kind == :subtitles && check.status == :ok }
    end
  end
end
