require "json"

if ARGV.shift == "toml-rb"
  require "toml-rb"
  parser = TomlRB.method(:parse)
else
  require "tomlib"
  parser = Tomlib.method(:load)
end
mode, path = ARGV
source = File.read(path, encoding: "UTF-8")
last = parser.call(source)
if mode == "verify"
  puts JSON.generate(last)
else
  STDOUT.sync = true
  STDIN.each_line do |line|
    count = Integer(line)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
    count.times { last = parser.call(source) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - start
    puts "#{elapsed} #{last.size}"
  end
end
