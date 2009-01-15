# Add lib to dir
begin
  dir = File.expand_path(File.dirname(__FILE__) + "/lib")
  $: << dir unless $:.include?(dir)
end
require 'red_steak'
