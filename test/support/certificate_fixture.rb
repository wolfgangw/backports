# frozen_string_literal: true
require 'dcp_inspect'
require 'nokogiri'

module CertificateFixture
  DS = 'http://www.w3.org/2000/09/xmldsig#'
  def signing_key
    @signing_key ||= OpenSSL::PKey::RSA.new(2048)
  end

  def certificate(cn, issuer: nil, ca: issuer.nil?, sha: 'sha256', encoding: OpenSSL::ASN1::PRINTABLESTRING, key: signing_key, issuer_key: signing_key)
    c = OpenSSL::X509::Certificate.new
    pkey = OpenSSL::ASN1::Sequence([OpenSSL::ASN1::Integer(key.n), OpenSSL::ASN1::Integer(key.e)]).to_der
    dnq = Base64.strict_encode64(OpenSSL::Digest::SHA1.digest(pkey))
    fields = [['O', 'Example'], ['OU', 'Example'], ['dnQualifier', dnq]].map { |f| [*f, OpenSSL::ASN1::PRINTABLESTRING] }
    fields += Array(cn).map { |value| ['CN', value, encoding] } unless cn.nil?
    c.subject = OpenSSL::X509::Name.new(fields)
    c.issuer = issuer ? issuer.subject : c.subject
    c.public_key = key.public_key
    c.serial = issuer ? issuer.serial.to_i + 1 : 1
    c.version = 2
    c.not_before = Time.utc(2026,1,1)
    c.not_after = Time.utc(2030,1,1)
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = c
    ef.issuer_certificate = issuer || c
    c.add_extension(ef.create_extension('basicConstraints', ca ? "CA:TRUE,pathlen:#{issuer ? 1 : 2}" : 'CA:FALSE', true))
    c.add_extension(ef.create_extension('keyUsage', ca ? 'keyCertSign' : 'digitalSignature,keyEncipherment', true))
    c.add_extension(ef.create_extension('authorityKeyIdentifier', 'issuer:always'))
    c.sign(issuer_key, OpenSSL::Digest.new(sha))
    c
  end

  def certificate_chain(cn = 'CS.Signer', root_cn: '.Root', sha: 'sha256')
    root = certificate(root_cn, sha: sha)
    [certificate(cn, issuer: root, sha: sha), root]
  end

  def sign_document(doc, chain, key: signing_key)
    leaf = chain.first
    signer = Nokogiri::XML::Node.new('Signer', doc)
    signer.namespace = doc.root.namespace
    signer.add_child("<ds:X509Data xmlns:ds='#{DS}'><ds:X509IssuerSerial><ds:X509IssuerName/><ds:X509SerialNumber>#{leaf.serial}</ds:X509SerialNumber></ds:X509IssuerSerial></ds:X509Data>")
    signer.at_xpath('.//ds:X509IssuerName', 'ds' => DS).content = leaf.issuer.to_s(OpenSSL::X509::Name::RFC2253)
    doc.root.add_child(signer)
    signature = Nokogiri::XML::DocumentFragment.parse("<ds:Signature xmlns:ds='#{DS}'><ds:SignedInfo><ds:CanonicalizationMethod Algorithm='http://www.w3.org/TR/2001/REC-xml-c14n-20010315'/><ds:SignatureMethod Algorithm='http://www.w3.org/2001/04/xmldsig-more#rsa-sha256'/><ds:Reference URI=''><ds:Transforms><ds:Transform Algorithm='http://www.w3.org/2000/09/xmldsig#enveloped-signature'/></ds:Transforms><ds:DigestMethod Algorithm='http://www.w3.org/2001/04/xmlenc#sha256'/><ds:DigestValue/></ds:Reference></ds:SignedInfo><ds:SignatureValue/><ds:KeyInfo><ds:X509Data>#{chain.map { |c| "<ds:X509Certificate>#{Base64.strict_encode64(c.to_der)}</ds:X509Certificate>" }.join}</ds:X509Data></ds:KeyInfo></ds:Signature>")
    digest = Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(doc.canonicalize))
    doc.root.add_child(signature)
    doc.at_xpath('//ds:DigestValue', 'ds' => DS).content = digest
    info = doc.at_xpath('//ds:SignedInfo', 'ds' => DS).canonicalize
    doc.at_xpath('//ds:SignatureValue', 'ds' => DS).content = Base64.strict_encode64(key.sign(OpenSSL::Digest::SHA256.new, info))
    doc
  end
end
