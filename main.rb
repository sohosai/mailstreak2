require 'open-uri'
require 'json'
require 'base64'
require 'kconv'
require './error_message'

class MailStreak < Sinatra::Base
  register Sinatra::ConfigFile
  config_file './config.yml'

  SMTP_HOST = settings.smtp_server['host']
  SMTP_PORT = settings.smtp_server['port']
  MAILBOOK  = settings.mailbook
  MAX_RCPTS = settings.max_rcpts
  DOMAIN    = settings.domain
  NO_REPLY  = "no-reply@#{DOMAIN}"
  LOG_DIR   = settings.log_dir

  configure do
    file = File.new("#{settings.root}/log/#{settings.environment}.log", 'a+')
    file.sync = true
    use Rack::CommonLogger, file
  end

  Mail.defaults do
    delivery_method :smtp, {
      address: SMTP_HOST,
      port:    SMTP_PORT,
    }
  end

  def get_emails(group)
    res = open("#{MAILBOOK}/groups/#{group}")
    code, message = res.status
    if code != '200'
      raise FailedToFetchMembers, "Failed to fetch members: #{group}"
    end
    members = JSON.parse(res.read)
    members.each_with_object("email").map(&:[]).select do |email|
      email.strip.length > 0
    end
  end

  def send_mail(original_from, from, to, rcpts, subject, body)
    mail = Mail.new do
      smtp_envelope_from NO_REPLY
      smtp_envelope_to   rcpts
      from               from
      to                 to
      subject            subject
      body               body
    end

    mail.header["X-Original-Sender"] = original_from
    mail.charset = 'UTF-8'

    mail.deliver!
  end

  def send_mail_to_group(original_from, group, subject, body)
    emails = get_emails(group)

    ml_address = "#{group}@#{DOMAIN}"
    ml_subject = "[#{group}] #{subject}"

    second_queue = []

    bulk_queue = emails.each_slice(MAX_RCPTS)
    bulk_queue.each do |rcpts|
      begin
        send_mail(original_from, ml_address, ml_address, rcpts, ml_subject, body)
        sleep 1
      rescue => err
        puts $!, $@
        puts "Failed to send email(bulk): #{rcpts}"
        second_queue += rcpts
      end
    end

    second_queue.each do |rcpt|
      begin
        send_mail(original_from, ml_address, ml_address, [rcpt], ml_subject, body)
        sleep 1
      rescue => err
        puts $!, $@
        puts "Failed to send email: #{rcpt}"
      end
    end
  end

  def reply_error(to, mes_id, body)
    mail = Mail.new do
      smtp_envelope_from NO_REPLY
      smtp_envelope_to   to
      to                 to
      from               NO_REPLY
      subject            ErrorMessage::ERROR_EMAIL_SUBJECT
      body               body
    end

    mail.reply_to = to
    mail.in_reply_to = mes_id
    mail.charset = 'UTF-8'

    mail.deliver!
  end

  def dump_mail(raw_mail)
    datetime = Time.now.strftime "%Y%m%d_%H%M%S"
    suffix = Random.rand(1000).to_s.rjust(3, '0')
    filename = "#{datetime}_#{suffix}.mail"
    File.write(File.join(LOG_DIR, filename), raw_mail)
  end

  class FailedToDecodeEmail < StandardError; end
  class EmptyEmail < StandardError; end
  class ReplyEmail < StandardError; end
  class FailedToFetchMembers < StandardError; end

  def get_contents(recv)
    subject = recv.subject
    body = ""
    if !recv.text_part && !recv.html_part
      body = recv.body.decoded.kconv(Encoding::UTF_8, recv.charset)
    elsif recv.text_part
      body = recv.text_part.decoded
    else
      raise FailedToDecodeEmail
    end

    if subject.nil? || subject.empty? || body.nil? || body.empty?
      raise EmptyEmail
    end

    unless subject.match(/^\s*Re:/i).nil?
      raise ReplyEmail
    end

    group = Mail::Address.new(recv.to.first).local
    [group, subject, body]
  end

  post '/' do
    request.body.rewind
    raw_mail = Base64.decode64(request.body.read)
    dump_mail(raw_mail)

    recv = Mail.read_from_string raw_mail
    from = recv.from
    mes_id = recv.message_id

    begin
      group, subject, body = get_contents recv
      send_mail_to_group(from, group, subject, body)
    rescue FailedToDecodeEmail
      reply_error from, mes_id, ErrorMessage::FAILED_TO_DECODE_EMAIL
    rescue EmptyEmail
      reply_error from, mes_id, ErrorMessage::EMPTY_EMAIL
    rescue ReplyEmail
      reply_error from, mes_id, ErrorMessage::REPLY_EMAIL
    rescue Mail::Field::ParseError
      reply_error from, mes_id, ErrorMessage::INVALID_MAILING_LIST
    rescue
      puts $!, $@
      reply_error from, mes_id, ErrorMessage::UNEXPECTED_ERROR
    end
  end
end
