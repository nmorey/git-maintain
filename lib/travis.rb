module GitMaintain
    class TravisCI < CI
        TRAVIS_URL='https://api.travis-ci.org/'

        def initialize(repo)
            super(repo)
            @url = TRAVIS_URL
        end

        private
        def getState(sha1, resp)
            br = findBranch(sha1, resp)
            return "not found" if br == nil

            return br["state"]
        end
        def getLog(sha1, resp)
            br = findBranch(sha1, resp)
            raise("Travis build not found") if br == nil
            job_id = br["job_ids"].last().to_s()
            return getJson(@url, "log_" + job_id, 'jobs/' + job_id + '/log', false)
        end
        def getTS(sha1, resp)
            br = findBranch(sha1, resp)
            raise("Travis build not found") if br == nil
            return br["started_at"]
        end
        def checkState(sha1, resp)
            return getState(sha1, resp) == "passed"
        end

        def getBrValidJson()
            return getJson(@url, :br_valid, 'repos/' + @repo.remote_valid + '/branches')
        end
        def getBrStableJson()
            return getJson(@url, :br_stable, 'repos/' + @repo.remote_stable + '/branches')
        end
        def findBranch(sha1, resp)
            log(:DEBUG_CI, "Looking for build for #{sha1}")
            resp["branches"].each(){|br|
                commit=resp["commits"].select(){|e| e["id"] == br["commit_id"]}.first()
                raise("Incomplete JSON received from Travis") if commit == nil
                log(:DEBUG_CI, "Found entry for sha #{commit["sha"]}")
                next if commit["sha"] != sha1
                return br
            }
            return nil
        end

        public
        def getValidState(br, sha1)
            return getState(sha1, getBrValidJson())
        end
        def checkValidState(br, sha1)
            return checkState(sha1, getBrValidJson())
        end
        def getValidLog(br, sha1)
            return getLog(sha1, getBrValidJson())
        end
        def getValidTS(br, sha1)
            return getTS(sha1, getBrValidJson())
        end

        def getStableState(br, sha1)
            return getState(sha1, getBrStableJson())
        end
        def checkStableState(br, sha1)
            return checkState(sha1, getBrStableJson())
        end
        def getStableLog(br, sha1)
            return getLog(sha1, getBrStableJson())
        end
        def getStableTS(br, sha1)
            return getTS(sha1, getBrStableJson())
        end
        def isErrored(status)
            return status == "failed" || status == "errored"
        end
    end
end
