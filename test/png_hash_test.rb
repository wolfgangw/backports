# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'support/inspection_fixture'

class PngHashTest < Minitest::Test
  include InspectionFixture

  def png_package
    File.binwrite(File.join(@directory, 'subtitle-image.dat'), "\x89PNG\r\n\x1a\n".b + 'image content')
    File.write(File.join(@directory, 'not-an-image.png'), 'ordinary asset')
    write_package(assets: [[6, 'subtitle-image.dat', 'image/png'], [7, 'not-an-image.png', 'application/octet-stream']])
  end

  def test_np_skips_observed_png_but_hashes_other_assets
    with_inspection_fixture do
      png_package
      # Same-size changes to both files leave the listed hashes stale.
      File.open(File.join(@directory, 'subtitle-image.dat'), 'r+b') { |io| io.seek(8); io.write('X') }
      File.open(File.join(@directory, 'not-an-image.png'), 'r+b') { |io| io.write('X') }
      result = inspect_fixture('--np', hashes: true)
      assets = result[:inspection_run].assets
      assert_equal 'skipped PNG (--np)', assets[fixture_uuid(6)].hash_status
      assert_nil assets[fixture_uuid(6)].hash_digest
      assert assets[fixture_uuid(6)].checks.any? { |check| check.kind == :hash && check.status == :skipped && check.message.include?('--np') }
      assert_equal 'mismatch', assets[fixture_uuid(7)].hash_status
      assert result[:hints].any? { |message| message.include?('--np') && message.include?(fixture_uuid(6)) }
      assert_includes result[:info], 'PNG asset hash checks skipped (--np): 1 asset'
      normal = inspect_fixture(hashes: true)
      assert_equal 'mismatch', normal[:inspection_run].assets[fixture_uuid(6)].hash_status
    end
  end

  def test_np_preserves_size_presence_and_hash_metadata_validation
    with_inspection_fixture do
      png_package
      path = File.join(@directory, 'PKL.xml')
      xml = Nokogiri::XML(File.read(path))
      xml.remove_namespaces!
      xml.at_xpath('//Asset/Hash').content = ''
      xml.root['xmlns'] = V::Interop_pkl
      File.write(path, xml.to_xml)
      File.open(File.join(@directory, 'subtitle-image.dat'), 'ab') { |io| io.write('extra') }
      File.unlink(File.join(@directory, 'not-an-image.png'))
      result = inspect_fixture('--np', hashes: true)
      assert result[:errors].any? { |message| message.include?('Size mismatch') }
      assert result[:errors].any? { |message| message.include?('Hash element is empty') }
      assert result[:errors].any? { |message| message.include?('Asset file missing') }
    end
  end

  def test_np_combines_with_size_limit_and_global_skip
    with_inspection_fixture do
      png_package
      result = inspect_fixture('--np', '--hl', '0.001KB', hashes: true)
      assert_equal 'skipped PNG (--np)', result[:inspection_run].assets[fixture_uuid(6)].hash_status
      assert_equal 'skipped by size', result[:inspection_run].assets[fixture_uuid(7)].hash_status
      assert_includes result[:info], 'Hash checks skipped by size for 1 asset of 2 total'
      result = inspect_fixture('--np')
      assert_equal 'skipped', result[:inspection_run].assets[fixture_uuid(6)].hash_status
      assert_includes result[:info], 'Hash checks skipped'
    end
  end

  def test_cli_and_both_engine_configuration_paths_agree
    configuration = DcpInspect::Configuration.new(skip_png_hashes: true)
    assert DcpInspect::CLI::Options.parse(['--np']).skip_png_hashes
    assert DcpInspect::CLI::Options.parse(configuration.cli_arguments).skip_png_hashes
    assert DcpInspect::CLI::Options.from_configuration(configuration).skip_png_hashes
    refute DcpInspect::CLI::Options.parse([]).skip_png_hashes
  end

  def test_small_file_digest_reports_only_observed_progress
    with_inspection_fixture do
      runtime = Runtime.new(options: DcpInspect::CLI::Options.parse([]), stdout: StringIO.new)
      logger = Object.new
      updates = []
      logger.define_singleton_method(:cr) { |line| updates << line }
      path = File.join(@directory, 'picture.mxf')
      digest, = runtime.digest_with_etabar('sha1', 'Hash', path, 20, '[= ]', nil, logger)
      assert_equal Digest::SHA1.file(path).digest, digest
      assert_equal 2, updates.size
      assert_includes updates.first, '0%'
      assert_includes updates.last, '100%'
    end
  end
end
