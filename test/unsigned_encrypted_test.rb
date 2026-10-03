# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'support/inspection_fixture'
require_relative 'support/certificate_fixture'

class UnsignedEncryptedTest < Minitest::Test
  include InspectionFixture
  include CertificateFixture

  def prepare(encrypted: true, key: true, sound_only: false)
    @metadata.each_value { |meta| meta['Label Set Type'] = 'SMPTE' }
    @metadata['picture.mxf'].merge!('EncryptedEssence' => 'Yes', 'CryptographicKeyID' => fixture_uuid(90)) if encrypted
    write_cpl(namespace: V::Smpte_cpl, reels: [reference('MainPicture', 4,
      key ? "<KeyId>urn:uuid:#{fixture_uuid(90)}</KeyId>" : '') + reference('MainSound', 5)])
    write_package(assets: sound_only ? [[5, 'sound.mxf', 'application/mxf']] : nil)
    path = File.join(@directory, 'PKL.xml')
    File.write(path, File.read(path).sub(V::Interop_pkl, V::Smpte_pkl))
  end

  def findings(result)
    result[:inspection_run].compositions.values.flat_map(&:checks).concat(
      result[:inspection_run].packing_lists.values.flat_map(&:checks)).select { |check| check.kind == :unsigned_encrypted }
  end

  def test_unsigned_encrypted_cpl_and_pkl_have_contextual_hints
    with_inspection_fixture do
      prepare
      checks = findings(inspect_fixture)
      assert_equal 2, checks.size
      assert checks.all? { |check| check.status == :hint }
      assert checks.any? { |check| check.message.include?('5.4.3.7') }
      assert checks.any? { |check| check.message.include?('5.5.2.3') }
    end
  end

  def test_missing_key_does_not_hide_observed_encryption
    with_inspection_fixture do
      prepare(key: false)
      assert_equal 2, findings(inspect_fixture).size
    end
  end

  def test_declared_encryption_is_labelled_and_not_attributed_to_pkl
    with_inspection_fixture do
      prepare(encrypted: false)
      checks = findings(inspect_fixture)
      assert_equal 1, checks.size
      assert_includes checks.first.message, 'essence encryption not confirmed'
    end
  end

  def test_plaintext_and_interop_do_not_receive_the_smpte_hint
    with_inspection_fixture do
      assert_empty findings(inspect_fixture)
      prepare(encrypted: false, key: false)
      assert_empty findings(inspect_fixture)
    end
  end

  def test_pkl_without_cpl_is_checked_using_its_own_assets
    with_inspection_fixture do
      prepare
      write_package(assets: [[4, 'picture.mxf', 'application/mxf']])
      path = File.join(@directory, 'PKL.xml')
      File.write(path, File.read(path).sub(V::Interop_pkl, V::Smpte_pkl))
      assert_equal 1, findings(inspect_fixture).size
      prepare(sound_only: true)
      assert_empty findings(inspect_fixture)
    end
  end

  def test_present_but_invalid_signatures_are_not_reported_as_unsigned
    with_inspection_fixture do
      prepare
      %w[CPL.xml PKL.xml].each do |name|
        path = File.join(@directory, name)
        doc = sign_document(Nokogiri::XML(File.read(path)), certificate_chain)
        doc.at_xpath('//*[local-name()="SignatureValue"]').content = 'broken'
        File.write(path, doc.to_xml)
      end
      result = inspect_fixture
      assert_empty findings(result)
      assert result[:errors].any? { |message| message.include?('Signature verification failure') }
    end
  end
end
