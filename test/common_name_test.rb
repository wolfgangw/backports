# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'support/certificate_fixture'

class CommonNameTest < Minitest::Test
  include CertificateFixture
  CN = DcpInspect::Crypto::CommonName
  Compliance = DcpInspect::Crypto::SignerCompliance

  def compliance(chain, role: 'CS')
    Compliance.new(chain.map(&:to_pem), desired_role: role)
  end

  def test_additional_known_and_unknown_roles_are_valid_for_content_signing
    ['CS.Signer', 'CS SM.Signer', 'CS Future.Signer', 'Future CS.Signer.v2'].each do |cn|
      result = compliance(certificate_chain(cn))
      assert result.valid?, result.errors.inspect
    end
  end

  def test_role_context_is_explicit_and_case_sensitive
    chain = certificate_chain('SM.Signer')
    assert compliance(chain, role: nil).valid?
    refute compliance(chain).valid?
    refute compliance(certificate_chain('cs.Signer')).valid?
    refute compliance(certificate_chain('.Signer'), role: nil).valid?
  end

  def test_missing_duplicate_and_malformed_names_are_findings_not_exceptions
    [nil, ['CS.One', 'CS.Two'], 'CS', 'CS.', 'CS  SM.Signer', ' CS.Signer', "CS\tSM.Signer", 'CS1.Signer', 'CS.Sïgner'].each do |cn|
      result = compliance(certificate_chain(cn))
      refute result.valid?, cn.inspect
      assert result.errors[:context].values.flatten.any? { |e| e.include?('CommonName') }, cn.inspect
    end
    root = certificate('.Root')
    leaf = certificate('CS.Signer', issuer: root, encoding: OpenSSL::ASN1::UTF8STRING)
    assert compliance([leaf, root]).errors[:context].values.flatten.any? { |m| m.include?('PrintableString') }
    parsed = CN.parse(certificate('CS SM.Vendor.Device.123', issuer: root).subject)
    assert_equal %w[CS SM], parsed[:roles]
    assert_equal 'Vendor.Device.123', parsed[:entity]
  end

  def test_issuer_syntax_and_authority_guidance_are_separate
    result = compliance(certificate_chain(root_cn: 'CS.Root'))
    assert result.valid?, result.errors.inspect
    assert result.hints[:context].values.flatten.any? { |m| m.include?('informative Annex A') }
    result = compliance(certificate_chain(root_cn: 'Root'))
    refute result.valid?
    assert result.errors[:context].values.flatten.any? { |m| m.start_with?('Issuer:') }
  end

  def test_interop_retains_historical_leaf_and_authority_policy
    assert compliance(certificate_chain('SM.Signer', sha: 'sha1')).valid?
    refute compliance(certificate_chain(root_cn: 'CS.Root', sha: 'sha1')).valid?
  end

  def test_absent_chain_has_safe_diagnostics
    result = compliance([])
    refute result.valid?
    refute result.chain_verified
    assert_empty result.errors[:context]
    assert_empty result.siginfo[:expired_certs]
    assert result.messages.any? { |m| m.include?('unchecked') }
  end
end
