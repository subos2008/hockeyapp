module HockeyApp
  class MultiplePagesError < StandardError
    def initialize(hash)
      @hash = hash
    end

    def to_s
      "More than one page of results received from HockeyApp and pagination is not implemented: received #{@hash["total_pages"]} pages with #{@hash["per_page"]} results per page. #{@hash["total_entries"]} total entries"
    end
  end

  class Client

    def initialize ws
      @ws = ws
    end

    def get_apps
        apps_hash = ws.get_apps
        assert_success apps_hash
        apps_hash["apps"].map{|app_hash|App.from_hash(app_hash, self)}
    end

    def get_crashes app
      crashes_hash = ws.get_crashes app.public_identifier
      assert_success crashes_hash
      crashes_hash["crashes"].map{|crash_hash|Crash.from_hash(crash_hash, app, self)}
    end

    def time_to_string time
      # Note: DateTime and Time convert differently to strings.
      # We should handle both.
      string = time.to_s
      string = string.sub(/ /, 'T')
      string = string.sub(/ ?\+.*$/, '')
      string = string.sub(/ ?UTC$/, '')
      return string
    end

    def get_crashes_for_version_between_times version, start_time, end_time, options = {}
      # The timezone used on hockeyapp's servers is UTC. 
      # Use a method call to convert to UTC if it's there.
      # Also convert to Time rather than DateTime if possible.
      begin
        start_time = start_time.to_time.utc
      rescue NoMethodError
      end
      begin
        end_time = end_time.to_time.utc
      rescue NoMethodError
      end
      since_string = time_to_string( start_time )
      till_string = time_to_string( end_time )
      # must use double quotes or hockeyapps servers silently error
      # and return all crashes for the variant.
      query_string = "[\"#{since_string}\" TO \"#{till_string}\"]'"
      crashes_hash = ws.query_crashes_for_version version.app.public_identifier, version.id, options.merge( {query: { per_page: 50, query: "created_at:#{query_string}"}})
      assert_success crashes_hash
      crashes_hash["crashes"].map{|crash_hash|Crash.from_hash(crash_hash, version.app, self)}
    end

    def get_crashes_for_crash_group group, options = {}
      crashes_hash = ws.get_crashes_for_group group.app.public_identifier, group.id, {query:options}
      assert_success crashes_hash
      crashes_hash["crashes"].map{|crash_hash|Crash.from_hash(crash_hash, group.app, self)}
    end

    def get_crash_groups app
      crash_groups_hash = ws.get_crash_groups app.public_identifier
      assert_success crash_groups_hash
      crash_groups_hash["crash_reasons"].map{|reason_hash|CrashGroup.from_hash(reason_hash, app, self)}
    end

    def get_crash_groups_for_version version, options = {}
      crash_groups_hash = ws.get_crash_groups_for_version version.app.public_identifier, version.id, {query:options}
      assert_success crash_groups_hash
      crash_groups_hash["crash_reasons"].map{|reason_hash|CrashGroup.from_hash(reason_hash, version.app, self)}
    end

    def get_crash_log crash
      ws.get_crash_log crash.app.public_identifier, crash.id
    end

    def get_crash_description crash
      ws.get_crash_description crash.app.public_identifier, crash.id
    end

    def get_versions app
      versions_hash = ws.get_versions app.public_identifier
      versions_hash["app_versions"].map{|version_hash|Version.from_hash(version_hash, app, self)}
    end

    def post_new_version version
      app_id = version.app.public_identifier
      ipa = version.ipa
      raise "There must be an executable file" if ipa.nil?
      version_hash = ws.post_new_version(app_id, ipa, version.dsym, version.notes, version.notes_type, version.notify, version.status, version.tags)
      raise version_hash['errors'].map{|e|e.to_s}.join("\n") unless version_hash['errors'].nil?
      Version.from_hash(version_hash, version.app, self)
    end

    def remove_app app
      resp = ws.remove_app app.public_identifier
      raise "unexpected response" if resp.code != 200
      resp.code == 200
    end

    def create_app file_ipa
      resp = ws.post_new_app(file_ipa)
      raise resp['errors'].map{|e|e.to_s}.join("\n") unless resp['errors'].nil?
      App.from_hash(resp, self)
    end



    private

    attr_reader :ws

    def assert_success hash
      status = hash["status"]
      raise "Bad Status : #{status}" unless status == "success"

      pages = hash["total_pages"]
      if pages.present?
        raise MultiplePagesError.new(hash) if pages > 1
      end
    end

  end
end
