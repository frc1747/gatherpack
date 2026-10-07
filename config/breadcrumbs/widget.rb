crumb :widgets do
  link "Dashboard Widgets", widgets_path
end

crumb :widget do |widget|
  link widget.new_record? ? "New widget" : widget.identifier_name, widget
  parent :widgets
end
