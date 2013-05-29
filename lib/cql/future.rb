# encoding: utf-8

require 'thread'


module Cql
  FutureError = Class.new(CqlError)

  # A future represents the value of a process that may not yet have completed.
  #
  class Future
    def initialize
      @complete_listeners = []
      @failure_listeners = []
      @value_barrier = Queue.new
      @state_lock = Mutex.new
    end

    # Combine multiple futures into a new future which completes when all
    # constituent futures complete, or fail when one or more of them fails.
    #
    # The value of the combined future is an array of the values of the
    # constituent futures.
    #
    # @param [Array<Future>] futures the futures to combine
    # @return [Future<Array>] an array of the values of the constituent futures
    #
    def self.combine(*futures)
      if futures.any?
        CombinedFuture.new(*futures)
      else
        completed([])
      end
    end

    # Creates a new future which is completed.
    #
    # @param [Object, nil] value the value of the created future
    # @return [Future] a completed future
    #
    def self.completed(value=nil)
      CompletedFuture.new(value)
    end

    # Creates a new future which is failed.
    #
    # @param [Error] error the error of the created future
    # @return [Future] a failed future
    #
    def self.failed(error)
      FailedFuture.new(error)
    end

    # Completes the future.
    #
    # This will trigger all completion listeners in the calling thread.
    #
    # @param [Object] v the value of the future
    #
    def complete!(v=nil)
      @state_lock.synchronize do
        raise FutureError, 'Future already completed' if complete? || failed?
        @value = v
        @complete_listeners.each do |listener|
          listener.call(@value)
        end
      end
    ensure
      @state_lock.synchronize do
        @value_barrier << :ping
      end
    end

    # Returns whether or not the future is complete
    #
    def complete?
      defined? @value
    end

    # Registers a listener for when this future completes
    #
    # @yieldparam [Object] value the value of the completed future
    #
    def on_complete(&listener)
      @state_lock.synchronize do
        if complete?
          listener.call(value)
        else
          @complete_listeners << listener
        end
      end
    end

    # Returns the value of this future, blocking until it is available, if necessary.
    #
    # If the future fails this method will raise the error that failed the future.
    #
    # @return [Object] the value of this future
    #
    def value
      raise @error if @error
      return @value if defined? @value
      @value_barrier.pop
      raise @error if @error
      return @value
    end
    alias_method :get, :value

    # Fails the future.
    #
    # This will trigger all failure listeners in the calling thread.
    #
    # @param [Error] error the error which prevented the value from being determined
    #
    def fail!(error)
      @state_lock.synchronize do
        raise FutureError, 'Future already completed' if failed? || complete?
        @error = error
        @failure_listeners.each do |listener|
          listener.call(error)
        end
      end
    ensure
      @state_lock.synchronize do
        @value_barrier << :ping
      end
    end

    # Returns whether or not the future is failed.
    #
    def failed?
      !!@error
    end

    # Registers a listener for when this future fails
    #
    # @yieldparam [Error] error the error that failed the future
    #
    def on_failure(&listener)
      @state_lock.synchronize do
        if failed?
          listener.call(@error)
        else
          @failure_listeners << listener
        end
      end
    end

    # Returns a new future representing a transformation of this future's value.
    #
    # @example
    #   future2 = future1.map { |value| value * 2 }
    #
    # @yieldparam [Object] value the value of this future
    # @yieldreturn [Object] the transformed value
    # @return [Future] a new future representing the transformed value
    #
    def map(&block)
      fp = Future.new
      on_failure { |e| fp.fail!(e) }
      on_complete do |v|
        begin
          vv = block.call(v)
          fp.complete!(vv)
        rescue => e
          fp.fail!(e)
        end
      end
      fp
    end

    # Returns a new future representing a transformation of this future's value,
    # but where the transformation itself may be asynchronous.
    #
    # @example
    #   future2 = future1.flat_map { |value| method_returning_a_future(value) }
    #
    # This method is useful when you want to chain asynchronous operations.
    #
    # @yieldparam [Object] value the value of this future
    # @yieldreturn [Future] a future representing the transformed value
    # @return [Future] a new future representing the transformed value
    #
    def flat_map(&block)
      fp = Future.new
      on_failure { |e| fp.fail!(e) }
      on_complete do |v|
        begin
          fpp = block.call(v)
          fpp.on_failure { |e| fp.fail!(e) }
          fpp.on_complete do |vv|
            fp.complete!(vv)
          end
        rescue => e
          fp.fail!(e)
        end
      end
      fp
    end
  end

  # @private
  class CompletedFuture < Future
    def initialize(value=nil)
      super()
      complete!(value)
    end
  end

  # @private
  class FailedFuture < Future
    def initialize(error)
      super()
      fail!(error)
    end
  end

  # @private
  class CombinedFuture < Future
    def initialize(*futures)
      super()
      values = [nil] * futures.size
      completed = [false] * futures.size
      futures.each_with_index do |f, i|
        f.on_complete do |v|
          all_done = false
          @state_lock.synchronize do
            values[i] = v
            completed[i] = true
            all_done = completed.all?
          end
          if all_done
            combined_complete!(values)
          end
        end
        f.on_failure do |e|
          unless failed?
            combined_fail!(e)
          end
        end
      end
    end

    alias_method :combined_complete!, :complete!
    private :combined_complete!

    alias_method :combined_fail!, :fail!
    private :combined_fail!

    def complete!(v=nil)
      raise FutureError, 'Cannot complete a combined future'
    end

    def fail!(e)
      raise FutureError, 'Cannot fail a combined future'
    end
  end
end