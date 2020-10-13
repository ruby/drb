# Distributed Ruby: dRuby

dRuby is a distributed object system for Ruby.  It allows an object in one
Ruby process to invoke methods on an object in another Ruby process on the
same or a different machine.

The Ruby standard library contains the core classes of the dRuby package.
However, the full package also includes access control lists and the
Rinda tuple-space distributed task management system, as well as a
large number of samples.  The full dRuby package can be downloaded from
the dRuby home page (see *References*).

For an introduction and examples of usage see the documentation to the
DRb module.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'drb'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install drb

## Usage

### dRuby in client/server mode

This illustrates setting up a simple client-server drb
system.  Run the server and client code in different terminals,
starting the server code first.

#### Server code

```
require 'drb/drb'

# The URI for the server to connect to
URI="druby://localhost:8787"

class TimeServer

  def get_current_time
    return Time.now
  end

end

# The object that handles requests on the server
FRONT_OBJECT=TimeServer.new

DRb.start_service(URI, FRONT_OBJECT)
# Wait for the drb server thread to finish before exiting.
DRb.thread.join
```

#### Client code

```
require 'drb/drb'

# The URI to connect to
SERVER_URI="druby://localhost:8787"

# Start a local DRbServer to handle callbacks.

# Not necessary for this small example, but will be required
# as soon as we pass a non-marshallable object as an argument
# to a dRuby call.

# Note: this must be called at least once per process to take any effect.
# This is particularly important if your application forks.
DRb.start_service

timeserver = DRbObject.new_with_uri(SERVER_URI)
puts timeserver.get_current_time
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby/drb.

