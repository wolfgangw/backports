# frozen_string_literal: true
require 'minitest/autorun'
require 'dcp_inspect'
require 'nokogiri'

class SignerIdentityTest < Minitest::Test
  Identity = DcpInspect::Crypto::SignerIdentity

  def setup
    @certificate = OpenSSL::X509::Certificate.new
    @certificate.serial = 42
    @certificate.issuer = OpenSSL::X509::Name.new([['O', 'Example, Inc.'], ['CN', 'Root']])
    @certificate.subject = OpenSSL::X509::Name.new([['O', 'Example'], ['CN', 'CS.Signer']])
  end

  def signer(issuer: 'CN=Root,O=Example\\, Inc.', serial: '42', subject: nil)
    doc = Nokogiri::XML('<Signer xmlns:ds="http://www.w3.org/2000/09/xmldsig#"><ds:X509Data><ds:X509IssuerSerial><ds:X509IssuerName/><ds:X509SerialNumber/></ds:X509IssuerSerial></ds:X509Data></Signer>')
    doc.at_xpath('//ds:X509IssuerName', Identity::NS).content = issuer
    doc.at_xpath('//ds:X509SerialNumber', Identity::NS).content = serial
    if subject
      node = Nokogiri::XML::Node.new('X509SubjectName', doc)
      node.namespace = doc.root.namespace_definitions.first
      node.content = subject
      doc.at_xpath('//ds:X509Data', Identity::NS).add_child(node)
    end
    doc.root
  end

  def test_escaped_names_and_different_string_encodings_match
    assert_empty Identity.errors(signer(subject: 'CN=CS.Signer,O=Example', serial: '+0042'), @certificate)
  end

  def test_equals_in_attribute_values_preserves_identity
    expected = Identity.distinguished_name(OpenSSL::X509::Name.new([['dnQualifier', 'abc+/=']]))
    assert_equal expected, Identity.parse_name('dnQualifier=abc\\+/=')
    assert_equal expected, Identity.parse_name('dnQualifier=abc\\+/\\=')
    assert_equal expected, Identity.parse_name('dnQualifier="abc+/="')
    refute_equal expected, Identity.parse_name('dnQualifier=abc\\+/')
  end

  def test_subject_is_optional
    assert_empty Identity.errors(signer, @certificate)
  end

  def test_separator_whitespace_does_not_change_identity
    assert_empty Identity.errors(signer(issuer: 'CN=Root, O=Example\\, Inc.'), @certificate)
    assert_equal Identity.parse_name('CN=Root+O=Example,OU=Authority'),
      Identity.parse_name("CN=Root+ O=Example,\n\tOU=Authority")
    # Dolby Unfold's issuer spelling includes both separator spaces and an
    # unescaped base64 padding equals sign.
    issuer = 'dnQualifier=GCx2vAlHzkdwGCcO8/RwVow0PAo=, CN=.Cinea.CA.1, O=DC256.Cinea.Com, OU=CA1.DC256.Cinea.Com'
    assert_equal Identity.parse_name(issuer.gsub(', ', ',')), Identity.parse_name(issuer)
  end

  def test_separator_tolerance_preserves_value_whitespace_and_escaped_commas
    expected = Identity.distinguished_name(OpenSSL::X509::Name.new([
      ['O', 'Example, Inc.'], ['CN', ' Root ']
    ]))
    assert_equal expected, Identity.parse_name('CN=\\20Root\\20, O=Example\\, Inc.')
    assert_equal expected, Identity.parse_name('CN=" Root ", O="Example, Inc."')
    refute_equal expected, Identity.parse_name('CN=Root, O=Example\\, Inc.')
    assert Identity.errors(signer(issuer: 'CN=Other, O=Example\\, Inc.'), @certificate).any? { |m| m.include?('issuer name mismatch') }
  end

  def test_issuer_subject_and_serial_mismatches_are_independent
    errors = Identity.errors(signer(issuer: 'CN=Other', subject: 'CN=Other', serial: '43'), @certificate)
    assert_equal 3, errors.size
    assert errors.any? { |m| m.include?('issuer name mismatch') }
    assert errors.any? { |m| m.include?('subject name mismatch') }
    assert errors.any? { |m| m.include?('serial mismatch') }
  end

  def test_invalid_or_missing_fields_do_not_raise
    errors = Identity.errors(signer(issuer: 'broken', serial: '42oops'), @certificate)
    assert_equal 2, errors.size
    assert_equal 2, Identity.errors(Nokogiri::XML('<Signer/>').root, @certificate).size
  end

  def test_serial_lookup_is_local_to_signer
    node = signer(serial: '43')
    node.document.root = Nokogiri::XML::Node.new('Root', node.document)
    node.document.root.add_child('<X509SerialNumber xmlns="http://www.w3.org/2000/09/xmldsig#">42</X509SerialNumber>')
    node.document.root.add_child(node)
    assert Identity.errors(node, @certificate).any? { |m| m.include?('serial mismatch') }
  end

  def test_rdn_grouping_is_significant
    refute_equal Identity.parse_name('CN=Root+O=Example'),
      Identity.parse_name('CN=Root,O=Example')
  end

  def test_identity_failure_changes_check_status_without_claiming_crypto_failure
    verifier = DcpInspect::Crypto::SignatureVerification.allocate
    verifier.instance_variable_set(:@signature_node, [Object.new])
    verifier.instance_variable_set(:@verified, true)
    verifier.instance_variable_set(:@identity_errors, ['Signer issuer name mismatch'])
    assert verifier.verified?
    assert_equal :error, verifier.check_status
  end
end
