# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'support/certificate_fixture'
require_relative 'support/inspection_fixture'

class ContentAuthenticatorTest < Minitest::Test
  include CertificateFixture
  include InspectionFixture
  Auth = DcpInspect::Crypto::ContentAuthenticator
  Compliance = DcpInspect::Crypto::SignerCompliance
  Signature = DcpInspect::Crypto::SignatureVerification

  def assess(chain, **args)
    Auth.assess(Compliance.new(chain.map(&:to_pem), desired_role: 'CS'), encrypted: true, signed: true, **args)
  end

  def test_eligibility_is_not_binding_and_checks_the_entire_chain
    result = assess(certificate_chain)
    assert_equal :eligible, result[:eligibility]
    assert_equal :unchecked, result[:binding]
    assert_equal :info, result[:status]
    assert_equal :error, assess(certificate_chain('CS SM.Signer'))[:status]
    assert_equal :error, assess(certificate_chain('CS Future.Signer'))[:status]
    root = certificate('.Root')
    intermediate = certificate('CS.Authority', issuer: root, ca: true)
    chain = [certificate('CS SM.Signer', issuer: intermediate), intermediate, root]
    result = assess(chain)
    assert_equal :eligible, result[:eligibility]
    assert_equal ['CS.Authority'], result[:candidates].map { |c| c[:subject][/CN=([^\/]+)/,1] }
    assert_equal :ok, assess(chain, content_authenticator: Auth.thumbprint(intermediate))[:status]
    assert_equal :error, assess(chain, content_authenticator: Auth.thumbprint(chain.first))[:status]
  end

  def test_binding_uses_smpte_certificate_thumbprint_not_public_key_or_whole_certificate
    chain = certificate_chain
    leaf = chain.first
    # Independently strip TBSCertificate TLV using its encoded length, retaining
    # all TBS contents. This differs from hashing the complete certificate DER.
    der = OpenSSL::ASN1.decode(leaf.to_der).value.first.to_der
    length_octets = der.getbyte(1) & 0x7f
    offset = der.getbyte(1) < 128 ? 2 : 2 + length_octets
    expected = Base64.strict_encode64(OpenSSL::Digest::SHA1.digest(der.byteslice(offset..)))
    assert_equal expected, Auth.thumbprint(leaf)
    assert_equal :ok, assess(chain, content_authenticator: "\n#{expected}\n")[:status]
    whole = Base64.strict_encode64(OpenSSL::Digest::SHA1.digest(leaf.to_der))
    dnq = leaf.subject.to_a.find { |f| f[0] == 'dnQualifier' }[1]
    [whole, dnq].each { |value| assert_equal :mismatch, assess(chain, content_authenticator: value)[:binding] }
    assert_equal :invalid, assess(chain, content_authenticator: 'garbage')[:binding]
  end

  def test_unusable_chain_is_unchecked_and_plaintext_is_not_subject_to_exclusivity
    assert_equal :unchecked, Auth.assess(Compliance.new([]), encrypted: true, signed: true)[:eligibility]
    assert_equal :not_applicable, Auth.assess(nil, encrypted: false, signed: true)[:eligibility]
    assert_equal :unchecked, Auth.assess(nil, encrypted: true, signed: false)[:eligibility]
  end

  def test_real_signatures_keep_cryptographic_and_certificate_results_separate
    ['CompositionPlaylist', 'PackingList'].each do |kind|
      doc = Nokogiri::XML("<#{kind} xmlns='urn:test'/>")
      sign_document(doc, certificate_chain('CS SM.Signer'))
      verifier = Signature.new(doc, desired_role: 'CS')
      assert verifier.verified?, verifier.messages.join("\n")
      assert_equal :ok, verifier.check_status
      doc = Nokogiri::XML("<#{kind} xmlns='urn:test'/>")
      sign_document(doc, certificate_chain('SM.Signer'))
      verifier = Signature.new(doc, desired_role: 'CS')
      assert verifier.verified?, verifier.messages.join("\n")
      assert_equal :error, verifier.check_status
      assert_equal :ok, verifier.verification_details[:cryptographic_signature]
      assert_equal :error, verifier.verification_details[:certificate_compliance]
      assert_match(/cryptographically verified; certificate/, verifier.messages.last)
    end
  end

  def sign_fixture(name, chain)
    path = File.join(@directory, name)
    doc = sign_document(Nokogiri::XML(File.read(path)), chain)
    File.write(path, doc.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML))
  end

  def test_encrypted_cpl_reports_dci_eligibility_independently_of_valid_signature
    with_inspection_fixture do
      key_id = fixture_uuid(90)
      @metadata['picture.mxf'].merge!('EncryptedEssence' => 'Yes', 'CryptographicKeyID' => key_id)
      write_cpl(reels: [reference('MainPicture', 4, "<KeyId>urn:uuid:#{key_id}</KeyId>") + reference('MainSound', 5)])
      sign_fixture('CPL.xml', certificate_chain('CS SM.Signer'))
      write_package
      result = inspect_fixture
      model = result[:inspection_run].compositions.values.first
      signature = model.checks.find { |c| c.kind == :signature }
      auth = model.checks.find { |c| c.kind == :dci_content_authenticator }
      assert_equal :ok, signature.status, result[:errors].inspect
      assert_equal :ok, signature.details[:cryptographic_signature]
      assert_equal :complete, model.completeness_status
      assert_equal :error, auth.status
      assert_equal :unchecked, auth.details[:binding]
      assert result[:errors].any? { |m| m.include?('DCI encrypted-CPL compatibility') }
      refute result[:errors].any? { |m| m.include?('Signature verification failure') }
    end
  end

  def test_broken_or_missing_signature_context_is_reported_without_aborting
    [:missing_signer, :missing_root, :broken_chain].each do |damage|
      with_inspection_fixture do
        chain = certificate_chain
        if damage == :broken_chain
          chain[0] = certificate('CS.Signer', issuer: chain.last, issuer_key: OpenSSL::PKey::RSA.new(2048))
        end
        doc = sign_document(Nokogiri::XML(File.read(File.join(@directory, 'CPL.xml'))), chain)
        doc.at_xpath('//*[local-name()="Signer"]').remove if damage == :missing_signer
        doc.xpath('//ds:X509Certificate', 'ds' => DS).last.remove if damage == :missing_root
        File.write(File.join(@directory, 'CPL.xml'), doc.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML))
        write_package
        result = inspect_fixture
        model = result[:inspection_run].compositions.values.first
        signature = model.checks.find { |c| c.kind == :signature }
        assert_equal :error, signature.status, damage.to_s
        assert_equal :complete, model.completeness_status
        assert_equal :unchecked, assess(chain)[:eligibility] if damage == :broken_chain
      end
    end
  end

  def test_plaintext_cpl_and_pkl_accept_extra_roles_and_malformed_names_do_not_abort
    with_inspection_fixture do
      chain = certificate_chain('CS Future.Signer')
      sign_fixture('CPL.xml', chain)
      write_package
      sign_fixture('PKL.xml', chain)
      result = inspect_fixture
      assert_empty result[:errors]
      assert_equal :ok, result[:inspection_run].packing_lists.values.first.checks.find { |c| c.kind == :signature }.status
      refute result[:inspection_run].compositions.values.first.checks.any? { |c| c.kind == :dci_content_authenticator }
      write_cpl
      sign_fixture('CPL.xml', certificate_chain(nil))
      write_package
      result = inspect_fixture
      assert result[:errors].any? { |m| m.include?('CommonName') }
      signature = result[:inspection_run].compositions.values.first.checks.find { |c| c.kind == :signature }
      assert_equal :ok, signature.details[:cryptographic_signature]
      assert_equal :error, signature.status
    end
  end
end
