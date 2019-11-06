module GitMaintain
    class CI

        def self.load(repo)
            repo_name = File.basename(repo.path)
            return GitMaintain::loadClass(CI, repo_name, repo)
        end

        def initialize(repo)
            GitMaintain::checkDirectConstructor(self.class)

            @repo = repo
            @cachedJson={}
        end

        private
        def log(lvl, str)
            GitMaintain::log(lvl, str)
        end

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
        def getJson(base_url, query_label, query, json=true)
            return @cachedJson[query_label] if @cachedJson[query_label] != nil
            url = base_url + query
            uri = URI(url)
            log(:INFO, "Querying CI...")
            log(:DEBUG_CI, url)
            response = fetch(uri)
            raise("CI request failed '#{url}'") if response.code.to_s() != '200'

            if json == true
                @cachedJson[query_label] = JSON.parse(response.body)
            else
                @cachedJson[query_label] = response.body
            end
            return @cachedJson[query_label]
        end

        public
        def getValidState(br, sha1)
            raise("Unimplemented")
        end
        def checkValidState(br, sha1)
            raise("Unimplemented")
        end
        def getValidLog(br, sha1)
            raise("Unimplemented")
        end
        def getValidTS(br, sha1)
            raise("Unimplemented")
        end

        def getStableState(br, sha1)
            raise("Unimplemented")
        end
        def checkStableState(br, sha1)
            raise("Unimplemented")
        end
        def getStableLog(br, sha1)
            raise("Unimplemented")
        end
        def getStableTS(br, sha1)
            raise("Unimplemented")
        end
        def emptyCache()
            @cachedJson={}
        end

        def isErrored(status)
            raise("Unimplemented")
        end
    end
end
