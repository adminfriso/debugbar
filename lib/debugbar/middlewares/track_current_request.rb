module Debugbar
  class TrackCurrentRequest
    def initialize(app)
      @app = app
    end

    def call(env)
      # we don't check if debugbar is enabled because this middleware is only added when it is

      # Set `ignore` attribute to reuse it anywhere
      Debugbar::Current.ignore = Debugbar.config.ignore_request?(env)

      return @app.call(env) if Debugbar::Current.ignore?

      req_id = SecureRandom.uuid
      Debugbar::Current.new_request!(req_id)

      status, headers, body = @app.call(env)

      # TODO: Remove this if statement?
      # We check meta because the frontend doesn't support request without meta yet.
      # It might happen with ActionController::Live where the following code
      # will run BEFORE ActionControllerEventSubscriber.process_action is called
      if Debugbar::Current.request&.meta
        RequestBuffer.push(Debugbar::Current.pop_request!)

        # TODO: Refactor since not having ActionCable might be more common than I thought
        payload = RequestBuffer.to_h
      
        # Validate JSON-encodability before broadcast; skip if it would crash
        begin
          ActiveSupport::JSON.encode(payload)   # will raise on invalid UTF-8
          ActionCable.server.broadcast("debugbar_channel", payload)
        rescue JSON::GeneratorError
          # Non-text/binary snuck into the payload (e.g. .xkt). Skip live update.
          # (Everything else — header, request logging, X-Debugbar-Url — still works.)
        end
      end

      # We can't use Rails.application.url_helper here because 1. we have to set up manually the hosts, 2. the route I
      # want is inside the engine routes and I didn't manage to access them via the helper
      headers["X-Debugbar-Url"] = "#{ActionDispatch::Request.new(env).base_url}#{Debugbar.config.prefix}/get/#{req_id}"

      [status, headers, body]
    end
  end

end
