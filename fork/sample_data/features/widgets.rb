# Three dashboard widgets: Markdown for everyone, a dynamic (ERB) widget for
# Programs managers, and one with its own CSS for Youth Program members.
Hbr::SampleData.feature "feature/widgets" do |s|
  s.enable_feature :widgets

  s.upsert!(Widget, { title: "Welcome to Northwind" },
    placement: "top", position: 0, viewer: "user", team: nil, dynamic: false, enabled: true, content: <<~MARKDOWN)
      This site holds **sample data**. Sign in as any of the `@example.com` logins
      (password `password123`) to see it from that person's side. The README in
      `fork/sample_data/` lists them all.
    MARKDOWN

  s.upsert!(Widget, { title: "Clocked In Now: Programs" },
    placement: "right", position: 0, viewer: "manager", team: s.team(:programs), dynamic: true, enabled: true,
    refresh_seconds: 60, content: <<~ERB)
      <% punches = TimeClockPunch.where(end_time: nil, person: Team.find_by!(name: "Programs").descendant_people).includes(:person).order(:start_time) %>
      <% if punches.any? %>
        <ul class="list-unstyled mb-0">
          <% punches.each do |punch| %>
            <li><%= h punch.person.identifier_name %>, since <%= l punch.start_time, format: :short %></li>
          <% end %>
        </ul>
      <% end %>
    ERB

  s.upsert!(Widget, { title: "Campout Checklist" },
    placement: "left", position: 0, viewer: "team", team: s.team(:youth), dynamic: false, enabled: true, style_mode: "theme",
    stylesheet: ".checklist li::marker { content: '✓ '; color: var(--bs-success); }", content: <<~MARKDOWN)
      <ul class="checklist">
        <li>Parent consent signed</li>
        <li>Sleeping bag and flashlight</li>
        <li>RSVP on the campout form</li>
      </ul>
    MARKDOWN

  s.report "#{Widget.count} widgets"
end
