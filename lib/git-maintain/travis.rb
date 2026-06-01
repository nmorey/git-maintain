# Main module for git-maintain repository maintenance tool.
module GitMaintain
    # CI adapter class for Travis CI integration.
    class TravisCI < CI
        # Base URL for Travis CI API.
        TRAVIS_URL='https://api.travis-ci.com/'

        # Initialize TravisCI adapter.
        #
        # @param repo [Repo] The Repo instance
        def initialize(repo)
            super(repo)
            @url = TRAVIS_URL
        end

        private
        # Get the Travis build status string for a specific commit SHA.
        #
        # @param sha1 [String] Commit SHA
        # @param resp [Hash] API response payload containing branch builds
        # @return [String] Build status string (e.g. 'passed', 'failed')
        def getState(sha1, resp)
            br = findBranch(sha1, resp)
            return "not found" if br == nil

            return br["state"]
        end

        # Fetch the build logs from Travis CI for a specific commit SHA.
        #
        # @param sha1 [String] Commit SHA
        # @param resp [Hash] API response payload
        # @return [String] Build log output text
        # @raise [GitMaintainError] If no build is found for the commit
        def getLog(sha1, resp)
            br = findBranch(sha1, resp)
            raise GitMaintainError.new("Travis build not found") if br == nil
            job_id = br["job_ids"].last().to_s()
            return getJson(@url, "travis_log_" + job_id, 'jobs/' + job_id + '/log', false)
        end

        # Get the Travis build timestamp for a specific commit SHA.
        #
        # @param sha1 [String] Commit SHA
        # @param resp [Hash] API response payload
        # @return [String] Build started-at timestamp string
        # @raise [GitMaintainError] If no build is found for the commit
        def getTS(sha1, resp)
            br = findBranch(sha1, resp)
            raise GitMaintainError.new("Travis build not found") if br == nil
            return br["started_at"]
        end

        # Check if the build status string represents success.
        #
        # @param sha1 [String] Commit SHA
        # @param resp [Hash] API response payload
        # @return [Boolean] True if build passed
        def checkState(sha1, resp)
            return getState(sha1, resp) == "passed"
        end

        # Fetch validation branch builds JSON payload from Travis CI API.
        #
        # @return [Hash] JSON API response
        # @raise [GitMaintainError] If API request fails
        def getBrValidJson()
            return getJson(@url, :travis_br_valid, 'repos/' + @repo.remote_valid + '/branches')
        end

        # Fetch stable branch builds JSON payload from Travis CI API.
        #
        # @return [Hash] JSON API response
        # @raise [GitMaintainError] If API request fails
        def getBrStableJson()
            return getJson(@url, :travis_br_stable, 'repos/' + @repo.remote_stable + '/branches')
        end

        # Find the specific branch build matching the given commit SHA.
        #
        # @param sha1 [String] Commit SHA
        # @param resp [Hash] API response branches payload
        # @return [Hash, nil] Branch build dictionary, or nil if not found
        # @raise [GitMaintainError] If API response is missing expected commit keys
        def findBranch(sha1, resp)
            log(:DEBUG_CI, "Looking for build for #{sha1}")
            resp["branches"].each(){|br|
                commit=resp["commits"].select(){|e| e["id"] == br["commit_id"]}.first()
                raise GitMaintainError.new("Incomplete JSON received from Travis") if commit == nil
                log(:DEBUG_CI, "Found entry for sha #{commit["sha"]}")
                next if commit["sha"] != sha1
                return br
            }
            return nil
        end

        public
        # Retrieve the validation build state for a specific branch and commit.
        #
        # @param br [Branch] The Branch instance
        # @param sha1 [String] Commit SHA
        # @return [String] Build status string (e.g. 'passed')
        def getValidState(br, sha1)
            return getState(sha1, getBrValidJson())
        end

        # Check if the validation build is successful.
        #
        # @param br [Branch] The Branch instance
        # @param sha1 [String] Commit SHA
        # @return [Boolean] True if build passed
        def checkValidState(br, sha1)
            return checkState(sha1, getBrValidJson())
        end

        # Retrieve the validation build log.
        #
        # @param br [Branch] The Branch instance
        # @param sha1 [String] Commit SHA
        # @return [String] Build log output text
        def getValidLog(br, sha1)
            return getLog(sha1, getBrValidJson())
        end

        # Retrieve the validation build timestamp.
        #
        # @param br [Branch] The Branch instance
        # @param sha1 [String] Commit SHA
        # @return [String] Build timestamp
        def getValidTS(br, sha1)
            return getTS(sha1, getBrValidJson())
        end

        # Retrieve the stable build state for a specific branch and commit.
        #
        # @param br [Branch] The Branch instance
        # @param sha1 [String] Commit SHA
        # @return [String] Build status string (e.g. 'passed')
        def getStableState(br, sha1)
            return getState(sha1, getBrStableJson())
        end

        # Check if the stable build is successful.
        #
        # @param br [Branch] The Branch instance
        # @param sha1 [String] Commit SHA
        # @return [Boolean] True if build passed
        def checkStableState(br, sha1)
            return checkState(sha1, getBrStableJson())
        end

        # Retrieve the stable build log.
        #
        # @param br [Branch] The Branch instance
        # @param sha1 [String] Commit SHA
        # @return [String] Build log output text
        def getStableLog(br, sha1)
            return getLog(sha1, getBrStableJson())
        end

        # Retrieve the stable build timestamp.
        #
        # @param br [Branch] The Branch instance
        # @param sha1 [String] Commit SHA
        # @return [String] Build timestamp
        def getStableTS(br, sha1)
            return getTS(sha1, getBrStableJson())
        end

        # Check if the CI build status represents an error/failure.
        #
        # @param br [Branch] The Branch instance
        # @param status [String] CI status string
        # @return [Boolean] True if build errored or failed
        def isErrored(br, status)
            return status == "failed" || status == "errored"
        end
    end
end
