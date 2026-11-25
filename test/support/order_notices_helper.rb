# Reads the notices a test sent. Needs ActiveJob::TestHelper.
module OrderNoticesHelper
  def enqueued_emails
    enqueued_jobs.select { |job| job[:job] == SendEmailJob }.map { |job| job[:args][1..3] }
  end

  # The addresses the emails went to, sorted.
  def emailed
    enqueued_emails.map(&:first).sort
  end

  def addresses(*people)
    people.map { |person| person.user.email }.sort
  end

  # The body of the one email sent to the person.
  def email_to(person)
    enqueued_emails.find { |address, _subject, _body| address == person.user.email }&.last
  end

  # Each person's Orders choice comes from GatherPack::Digests.delivery_for
  # for the block, as Summaries' Email notices page gives it, whether or not
  # that seam is merged here. choices: { person => :each, :daily, :weekly or
  # :off }; anyone else gets the site's choice. handles: is what
  # GatherPack::Digests.handles?(:orders) and enabled? say.
  def with_personal_choices(choices = {}, handles: false, **people)
    choices = choices.merge(people) if people.any?
    added = !defined?(GatherPack::Digests)
    if added
      GatherPack.const_set(:Digests, Module.new)
      GatherPack::Digests.const_set(:Section, Data.define(:heading, :body, :link, :link_label))
    end
    seam = GatherPack::Digests
    names = %i[delivery_for handles? enabled?]
    saved = names.select { |name| seam.respond_to?(name) }.index_with { |name| seam.method(name) }
    seam.define_singleton_method(:delivery_for) { |_key, person| choices.fetch(person) { Orders::Config.notices } }
    seam.define_singleton_method(:handles?) { |_key| handles }
    seam.define_singleton_method(:enabled?) { handles }
    yield
  ensure
    if added
      GatherPack.send(:remove_const, :Digests)
    elsif seam
      names.each { |name| seam.singleton_class.send(:remove_method, name) }
      saved.each { |name, method| seam.define_singleton_method(name, method) }
    end
  end
end
