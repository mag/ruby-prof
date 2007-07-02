require 'rake'
require 'ruby-prof/task'

PROFILE_OUTPUT_DIR = "test/profile"

namespace :ruby_prof do
  # Create tasks for each set of unit tests
  %w[unit functional helper integration].each do |target|
    task_name = "rails:#{target}"
    RubyProf::ProfileTask.new(target) do |t|
      t.libs << "test"
      t.test_files = FileList["test/#{target}/*_test.rb"]
      t.output_dir = PROFILE_OUTPUT_DIR
    end
  end
  
  desc "Run rails profiling tests"
  task 'rails' => 'db:test:prepare' do |task|
    # Remove old files
    files = Dir.glob(PROFILE_OUTPUT_DIR + '/*')
    FileUtils.rm(files)

    # Run the tasks    
    %w[unit functional helper integration].each do |target|
      task_name = "ruby_prof:rails:#{target}"
      begin
        Rake::Task[task_name].invoke
      rescue => e
        STDOUT << e.to_s
        # eat it - keep going
      end
    end
  end
  
  test = RubyProf::ProfileTask.new('test') do |t|
    t.test_files = FileList['test/unit/c*.rb']
    t.output_dir = "test/profile"
    t.printer = :graph_html
    t.min_percent = 10
  end
  
  task test => :environment
end
