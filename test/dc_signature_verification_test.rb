# frozen_string_literal: true

require 'minitest/autorun'
require 'dcp_inspect'

class DCSignatureVerificationTest < Minitest::Test
  FIXTURE_PATH = File.expand_path('fixtures/pkl_missing_signature_method.xml', __dir__)

  def setup
    @verifier = DcpInspect::Crypto::SignatureVerification.allocate
    @verifier.instance_variable_set(:@messages, [])
  end

  def test_doc_signature_method_algorithm_handles_missing_element
    doc = Class.new do
      def at_xpath(*)
        nil
      end
    end.new

    assert_nil @verifier.send(:doc_signature_method_algorithm, doc, {}, 'ds')
    assert_includes @verifier.messages, 'SignatureMethod node missing ❌'
  end

  def test_check_signature_value_stops_when_signature_method_missing
    pub_k = Object.new
    def pub_k.n
      1
    end

    @verifier.define_singleton_method(:doc_signature_method_algorithm) { |*| nil }
    refute @verifier.send(:check_signature_value, Object.new, {}, 'ds', pub_k)

    assert_includes @verifier.messages, 'Cannot verify signature value: SignatureMethod Algorithm missing ❌'
  end

  def test_doc_reference_digest_value_handles_missing_element
    reference = Class.new do
      def at_xpath(*)
        nil
      end
    end.new

    assert_nil @verifier.send(:doc_reference_digest_value, reference, {}, 'ds')
    assert_includes @verifier.messages, 'Reference missing DigestValue element ❌'
  end

  def test_check_references_stops_when_digest_data_missing
    reference = Struct.new(:attributes) do
      def at_xpath(*)
        nil
      end
    end.new({ 'URI' => Struct.new(:value).new('') })

    @verifier.define_singleton_method(:doc_references) { |*| [reference] }
    @verifier.define_singleton_method(:doc_reference_digest_method_algorithm) { |*| 'sha1' }
    refute @verifier.send(:check_references, Object.new, {}, 'ds')

    assert_includes @verifier.messages, 'Reference missing DigestValue element ❌'
    assert_includes @verifier.messages, 'Cannot verify reference digest: DigestMethod or DigestValue missing ❌'
  end

  def test_fixture_missing_signature_method_documented
    xml = File.read(FIXTURE_PATH)
    refute_includes xml, '<SignatureMethod'
  end
end
