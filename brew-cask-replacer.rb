#!/usr/bin/env ruby
require 'fileutils'

USERNAME = 'username'
UID = 'uid'
GID = 'gid'

# Drops privileges to that of the specified user
def drop_priv user
  Process.initgroups(user.username, user.gid)
  Process::Sys.setegid(user.gid)
  Process::Sys.setgid(user.gid)
  Process::Sys.setuid(user.uid)
end

# Execute the provided block in a child process as the specified user
# The parent blocks until the child finishes.
def do_as_user user
  read, write = IO.pipe
  unless pid = fork
    drop_priv(user)
    result = yield if block_given?
    Marshal.dump(result, write)
    exit! 0 # prevent remainder of script from running in the child process
  end
  write.close
  result = read.read
  Process.wait(pid)
  Marshal.load(result)
end

at_exit { puts 'Script finished.' }

User = Struct.new(:username, :uid, :gid)
user = User.new(USERNAME, UID, GID)

exclude = []

Dir.glob('/Applications/*.app').each do |path|
  next if File.symlink?(path)

  # Remove version numbers at the end of the name
  app = path.slice(14..-1).sub(/.app\z/, '').sub(/ \d*\z/, '')
  searchresult = do_as_user(user) do
    `brew cask search #{app}`
  end
  next unless searchresult =~ /Exact match/
  puts searchresult

  token = searchresult.split("\n")[1]

  next unless exclude.grep(/#{token}/).empty?

  puts "Installing #{token}..."
  begin
    FileUtils.mv(path, File.expand_path('~/.Trash/'))
  rescue Errno::EPERM, Errno::EEXIST
    puts "ERROR: Could not move #{path} to Trash"
    next
  end

  do_as_user(user) do
    puts `brew cask install #{token} --appdir=/Applications`
  end
end
