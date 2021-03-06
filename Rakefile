require 'rubygems'
require 'rake/gempackagetask'
require 'rake/testtask'

require 'lib/perry/version'

spec = Gem::Specification.new do |s|
  s.name             = 'perry'
  s.version          = Perry::Version.to_s
  s.has_rdoc         = true
  s.extra_rdoc_files = %w(README.rdoc)
  s.rdoc_options     = %w(--main README.rdoc)
  s.summary          = "Ruby library for querying and mapping data through generic interfaces"
  s.author           = 'Travis Petticrew'
  s.email            = 'bobo@petticrew.net'
  s.homepage         = 'http://github.com/tpett/perry'
  s.files            = %w(README.rdoc Rakefile) + Dir.glob("{lib}/**/*")
  # s.executables    = ['perry']

  s.add_development_dependency("shoulda", [">= 2.10.0"])
  s.add_development_dependency("leftright", [">= 0.0.6"])
  s.add_development_dependency("fakeweb", [">= 1.3.0"])
  s.add_development_dependency("factory_girl", [">= 0"])

  s.add_dependency("activesupport", [">= 2.3.0"])
  s.add_dependency("bertrpc", [">= 1.3.0"])
  s.add_dependency("json", [">=1.4.6"])
end

Rake::GemPackageTask.new(spec) do |pkg|
  pkg.gem_spec = spec
end

[:rails2, :rails3].each do |name|

  Rake::TestTask.new("test_#{name}") do |t|
    t.libs << 'test'
    t.ruby_opts << "-r load_#{name}"
    t.test_files = FileList["test/**/*_test.rb"]
    t.verbose = true
  end

end

desc "Test all gem versions"
task :test => [:test_rails2, :test_rails3] do
end

begin
  require 'rcov/rcovtask'

  Rcov::RcovTask.new(:coverage) do |t|
    t.libs       = ['test']
    t.test_files = FileList["test/**/*_test.rb"]
    t.verbose    = true
    t.rcov_opts  = ['--text-report', "-x #{Gem.path.join(',')}", '-x /Library/Ruby', '-x /usr/lib/ruby']
  end

  task :default => :coverage

rescue LoadError
  warn "\n**** Install rcov (sudo gem install relevance-rcov) to get coverage stats ****\n"
  task :default => :test
end

desc 'Generate the gemspec to serve this gem'
task :gemspec do
  file = File.dirname(__FILE__) + "/#{spec.name}.gemspec"
  File.open(file, 'w') {|f| f << spec.to_ruby }
  puts "Created gemspec: #{file}"
end
