module Backport
    class TravisChecker
        TRAVIS_URL='https://api.travis-ci.org/'

        def initialize(repo)
            @repo = repo
            @cachedJson={}
        end

        private
        def fetch(uri_str, limit = 10)
            # You should choose a better exception.
            raise ArgumentError, 'too many HTTP redirects' if limit == 0

            response = Net::HTTP.get_response(URI(uri_str))

            case response
            when Net::HTTPSuccess then
                response
            when Net::HTTPRedirection then
                location = response['location']
                fetch(location, limit - 1)
            else
                response.value
            end
        end
        def getJson(query_label, query, json=true)
            return @cachedJson[query_label] if @cachedJson[query_label] != nil
            url = TRAVIS_URL + query
            uri = URI(url)
            puts "# Querying travis..."
            puts "# #{url}" if ENV["DEBUG_TRAVIS"].to_s() != ""
            response = fetch(uri)
            raise("Travis request failed '#{url}'") if response.code.to_s() != '200'

            if json == true
                @cachedJson[query_label] = JSON.parse(response.body)
            else
                @cachedJson[query_label] = response.body
            end
            return @cachedJson[query_label]
        end
        def getState(sha1, resp)
            br = findBranch(sha1, resp)
            return "not found" if br == nil

            return br["state"]
        end
        def getLog(sha1, resp)
            br = findBranch(sha1, resp)
            raise("Travis build not found") if br == nil
            job_id = br["job_ids"].last().to_s()
            return getJson("log_" + job_id, 'jobs/' + job_id + '/log', false)
        end
        def checkState(sha1, resp)
            return getState(sha1, resp) == "passed"
        end

        def getBrValidJson()
            return getJson(:br_valid, 'repos/' + @repo.remote_valid + '/branches')
        end
        def getBrStableJson()
            return getJson(:br_stable, 'repos/' + @repo.remote_stable + '/branches')
        end
        def findBranch(sha1, resp)
            puts "# Looking for build for #{sha1}" if ENV["DEBUG_TRAVIS"].to_s() != ""
            resp["branches"].each(){|br|
                commit=resp["commits"].select(){|e| e["id"] == br["commit_id"]}.first()
                raise("Incomplete JSON received from Travis") if commit == nil
                puts "# Found entry for sha #{commit["sha"]}" if ENV["DEBUG_TRAVIS"].to_s() != ""
                next if commit["sha"] != sha1
                return br
            }
            return nil
        end

        public
        def getValidState(sha1)
            return getState(sha1, getBrValidJson())
        end
        def checkValidState(sha1)
            return checkState(sha1, getBrValidJson())
        end
        def getValidLog(sha1)
            return getLog(sha1, getBrValidJson())
        end

        def getStableState(sha1)
            return getState(sha1, getBrStableJson())
        end
        def checkStableState(sha1)
            return checkState(sha1, getBrStableJson())
        end
        def getStableLog(sha1)
            return getLog(sha1, getBrStableJson())
        end
    end
end
