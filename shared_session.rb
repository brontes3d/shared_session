class MemcacheSharedSession < Rack::Session::Cookie
  
  def self.memcache_connection
	  require 'memcache'
    #TODO: make this more configurable (in a better way)
    #TODO: save and re-use connection to memcache?
    MemCache.new(*MEMCACHE_CONFIG)
  end
  
  def initialize(app, options={})
    @@allow_write = options[:allow_write] #defaults to false
    @@memcache_key_prefix = options[:memcache_key_prefix] || ""
    super
  end
  
  def self.memcache_key_prefix
    @@memcache_key_prefix ||= ""
  end
  
  def load_session(env)
    old_val = env["rack.session"]
    old_val_opts = env["rack.session.options"]
    env["rack.session"] = Hash.new
    r = super
    loaded_into = env["rack.session"]
    if @memcache_key = loaded_into['key']
      m = MemcacheSharedSession.memcache_connection
      env['shared_session'] = m.get(@@memcache_key_prefix + @memcache_key) || Hash.new
      Rails.logger.info { "Loaded #{env['shared_session'].inspect} from shared session key #{@memcache_key}" }
    else
      @memcache_key = ActiveSupport::SecureRandom.hex(16)
      env['shared_session'] = Hash.new
    end
    r
  ensure
    env["rack.session"] = old_val
    env["rack.session.options"] = old_val_opts
  end
  
  def commit_session(env, status, headers, body)
    old_val = env["rack.session"]
    old_val_opts = env["rack.session.options"]
    env["rack.session"] = {'key' => @memcache_key}
    #workaround for:
    # Rails set cookie to blank string assuming this means we'll write a blank to the response
    # rack sees a String for Set-Cookie and assumes there's a previous value
    # undesirable result is a Set-Cookie line that begins with a \n
    # solution is to set to nil as rack would expect if it's blank
    if headers["Set-Cookie"].blank?
      headers["Set-Cookie"] = nil
    end
    r = super
    if @@allow_write
      m = MemcacheSharedSession.memcache_connection
      shared_session = env["shared_session"]
      Rails.logger.info { "Saved #{shared_session.inspect} in shared session key #{@memcache_key}" }
      #m.flush_all is a way to reset memcache in testing....
      m.set(@@memcache_key_prefix + @memcache_key, shared_session) #TODO: don't expire in 60 seconds
    end
    r
  ensure
    env["rack.session"] = old_val
    env["rack.session.options"] = old_val_opts
  end
  
end

ActionController::Dispatcher.middleware.use MemcacheSharedSession, SHARED_SESSION_CONFIG

module SharedSession
  
  def shared_session
    request.env['shared_session']
  end
  
  def shared_session=(arg)
    request.env['shared_session'] = arg
  end
  
  def clear_shared_session!
    request.env['shared_session'] = nil
  end
  
end