module GitMaintain
    class AzureCI < CI
        AZURE_URL='https://dev.azure.com/'

        def initialize(repo, stable='', valid='')
            super(repo)
            @url = AZURE_URL
            @stable_org=stable
            @valid_org=valid
        end

        private
        def getState(sha1, resp)
            br = findBranch(sha1, resp)
            return "not found" if br == nil
            return "running" if br["result"] == nil
            return br["result"].to_s()
        end
        def getLog(sha1, resp)
            str=""
            # br = findBranch(sha1, resp)
            # raise("Travis build not found") if br == nil
            # job_id = br["id"].to_s()
            # logs= getJson(@url, "azure_log_list" + job_id,
            #               @repo.name + "/_apis/build/builds/#{job_id}/logs?api-version=5.1")
            # 1.upto(logs["count"]) { |x|
            #     log(:DEBUG_CI, "Downloading log file #{x}/#{logs["count"]}")
            #      nzstr = getJson(@url, "azure_log_" + job_id + '_' + x.to_s(),
            #               @repo.name + "/_apis/build/builds/#{job_id}/logs/#{x}?api-version=5.1", false)
            # # This is zipped. We need to extract it
            # }
            return str
        end
        def getTS(sha1, resp)
            br = findBranch(sha1, resp)
            raise("Travis build not found") if br == nil
            return br["started_at"]
        end
        def checkState(sha1, resp)
            st = getState(sha1, resp)
            return  st == "passed"  || st == "succeeded"
        end

        def getBrValidJson()
            raise("Validation organisation not provided") if @valid_org == ''
            return getJson(@url + @valid_org + '/',
                           :azure_br_valid, @repo.name + '/_apis/build/builds?api-version=5.1')
        end
        def getBrStableJson()
            raise("Stable organisation not provided") if @stable_org == ''
            return getJson(@url + @stable_org + '/',
             :azure_br_stable, @repo.name + '/_apis/build/builds?api-version=5.1')
        end
        def findBranch(sha1, resp)
            log(:DEBUG_CI, "Looking for build for #{sha1}")
            resp["value"].each(){|br|
                commit= br["sourceVersion"]
                raise("Incomplete JSON received from Travis") if commit == nil
                log(:DEBUG_CI, "Found entry for sha #{commit}")
                next if commit != sha1
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
        def isErrored(br, status)
            # https://docs.microsoft.com/en-us/rest/api/azure/devops/build/builds/list?
            # view=azure-devops-rest-5.1#buildresult
            return status == "failed"
        end
    end
end
