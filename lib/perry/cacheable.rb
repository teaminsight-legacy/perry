require 'perry/cacheable/store'
require 'perry/cacheable/entry'
require 'digest/md5'

module Perry::Cacheable

  module ClassMethods

    # TRP: Default to a 5 minute cache
    DEFAULT_LONGEVITY = 5*60
    @@cache_store = nil

    def reset_cache_store(default_longevity=DEFAULT_LONGEVITY)
      @@cache_store = Perry::Cacheable::Store.new(default_longevity)
    end

    def cache_store
      @@cache_store
    end

    protected

    def fetch_records_with_caching(relation)
      options = relation.to_hash
      key = Digest::MD5.hexdigest(self.to_s + options.to_a.sort { |a,b| a.to_s.first <=> b.to_s.first }.inspect)
      cache_hit = self.cache_store.read(key)
      get_fresh = options.delete(:fresh)

      if cache_hit && !get_fresh
        self.read_adapter.log(options, "CACHE #{self.name}")
        cache_hit.each { |fv| fv.fresh = false.freeze }
        cache_hit
      else
        fresh_value = fetch_records_without_caching(relation)

        # TRP: Only store in cache if record count is below the cache_record_count_threshold (if it is set)
        if !self.cache_record_count_threshold || fresh_value.size <= self.cache_record_count_threshold
          self.cache_store.write(key, fresh_value, (self.cache_expires) ? fresh_value[0].send(self.cache_expires) : Time.now + DEFAULT_LONGEVITY) unless fresh_value.empty?
          fresh_value.each { |fv| fv.fresh = true.freeze }
        end

        fresh_value
      end
    end

    def enable_caching(options)
      reset_cache_store unless cache_store
      self.cacheable = true
      self.cache_expires = options[:expires]
      self.cache_record_count_threshold = options[:record_count_threshold]
    end

  end

  module InstanceMethods

    def fresh?
      @fresh
    end

  end

  def self.included(receiver)
    receiver.class_inheritable_accessor :cache_expires, :cache_record_count_threshold
    receiver.send :attr_accessor, :fresh

    receiver.extend         ClassMethods
    receiver.send :include, InstanceMethods

    # TRP: Remap calls for RPC through the caching mechanism
    receiver.class_eval do
      class << self
        alias_method :fetch_records_without_caching, :fetch_records
        alias_method :fetch_records, :fetch_records_with_caching
      end
    end

  end

end