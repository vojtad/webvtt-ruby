# frozen_string_literal: true

require 'minitest/test_task'

Minitest::TestTask.create # named test, sensible defaults

# or more explicitly:

Minitest::TestTask.create(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.warning = false
  t.test_globs = ['tests/**/*.rb']
end

task default: :test
