require 'test_helper'

# test cases for PGP inline signed messages (i.e. non-mime)
class InlineSignedMessageTest < Test::Unit::TestCase

  context "InlineSignedMessage" do

    setup do
      (@mails = Mail::TestMailer.deliveries).clear
      @mail = Mail.new do
        to 'jane@foo.bar'
        from 'joe@foo.bar'
        subject 'test'
        body 'i am unencrypted'
      end
    end

    context 'strip_inline_signature' do
      should 'strip signature from signed text' do
        body = self.class.inline_sign(@mail, 'i am signed')
        assert stripped_body = Mail::Gpg.strip_inline_signature(body)
        assert_equal 'i am signed', stripped_body
      end

      should 'not change unsigned text' do
        assert stripped_body = Mail::Gpg.strip_inline_signature("foo\nbar\n")
        assert_equal "foo\nbar", stripped_body
      end
    end

    context "signed message" do
      should "verify body" do
        mail = Mail.new(@mail)
        mail.body = self.class.inline_sign(mail, mail.body.to_s)
        assert !mail.multipart?
        assert mail.signed?
        assert mail.signature_valid?
        assert vr = mail.verify_result
        assert sig = vr.signatures.first
        assert sig.to_s=~ /Joe/
        assert sig.valid?
      end

      should "detect invalid sig" do
        mail = Mail.new(@mail)
        mail.body = self.class.inline_sign(mail, mail.body.to_s).gsub /i am/, 'i was'
        assert !mail.multipart?
        assert mail.signed?
        assert !mail.signature_valid?
        assert vr = mail.verify_result
        assert sig = vr.signatures.first
        assert sig.to_s=~ /Joe/
        assert !sig.valid?
      end

    end

    context "message with signed attachment" do
      should "check attachment signature" do
        mail = Mail.new(@mail)
        mail.body = 'foobar'
        mail.part do |p|
          p.body = self.class.inline_sign(mail, 'sign me!')
        end
        assert mail.multipart?
        assert mail.signed?
        assert mail.signature_valid?
        assert vr = mail.parts.last.verify_result
        assert !mail.parts.first.signed?
        assert mail.parts.last.signed?
        assert Mail::Gpg.signed_inline?(mail.parts.last)
        assert_equal [vr], mail.verify_result
        assert sig = vr.signatures.first
        assert sig.to_s=~ /Joe/
        assert sig.valid?
      end

      should "detect invalid sig" do
        mail = Mail.new(@mail)
        mail.body = 'foobar'
        mail.part do |p|
          p.body = self.class.inline_sign(mail, 'i am signed!').gsub /i am/, 'i was'
        end
        mail.part do |p|
          p.body = self.class.inline_sign(mail, 'i am signed!')
        end

        assert mail.multipart?
        assert mail.signed?
        assert !mail.signature_valid?
        assert vr = mail.verify_result
        assert_equal 2, vr.size

        invalid = mail.parts[1]
        assert !invalid.signature_valid?
        assert sig = invalid.verify_result.signatures.first
        assert sig.to_s=~ /Joe/
        assert !sig.valid?

        valid = mail.parts[2]
        assert valid.signature_valid?
        assert sig = valid.verify_result.signatures.first
        assert sig.to_s=~ /Joe/
        assert sig.valid?
      end
    end
  end


  def self.inline_sign(mail, plain, armor = true)
    GPGME::Crypto.new.clearsign(plain,
      password: 'abc',
      signers: mail.from,
      armor: armor).to_s
  end

end

