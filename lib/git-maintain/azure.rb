# Main module for git-maintain repository maintenance tool.
module GitMaintain
    # CI adapter class for Azure DevOps Pipelines integration.
    class AzureCI < CI
        # Base URL for Azure DevOps services.
        AZURE_URL='https://dev.azure.com/'

        # Initialize the AzureCI adapter.
        #
        # @param repo [Repo] The Repo instance
        # @param stable [String] Name of the stable Azure DevOps organization
        # @param valid [String] Name of the validation Azure DevOps organization
        def initialize(repo, stable='', valid='')
            super(repo)
            @url = AZURE_URL
            @stable_org=stable
            @valid_org=valid
        end

        private
        # Get the Azure build status string for a specific commit SHA.
        #
        # @param sha1 [String] Commit SHA
        # @param resp [Hash] API response payload containing builds
        # @return [String] Build status string (e.g. 'succeeded', 'started', 'failed')
        def getState(sha1, resp)
            br = findBranch(sha1, resp)
            return "not found" if br == nil
            return "started" if br["result"] == nil
            return br["result"].to_s()
        end

        # Retrieve the build logs from Azure DevOps.
        #
        # @param sha1 [String] Commit SHA
        # @param resp [Hash] API response payload
        # @return [String] Empty string placeholder (log fetching is handled by Azure pipelines)
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

        # Get the Azure build timestamp for a specific commit SHA.
        #
        # @param sha1 [String] Commit SHA
        # @param resp [Hash] API response payload
        # @return [String] Build startTime timestamp string
        # @raise [GitMaintainError] If no build is found for the commit
        def getTS(sha1, resp)
            br = findBranch(sha1, resp)
            raise GitMaintainError.new("Travis build not found") if br == nil
            return br["startTime"]
        end

        # Check if the Azure build status string represents success.
        #
        # @param sha1 [String] Commit SHA
        # @param resp [Hash] API response payload
        # @return [Boolean] True if build succeeded or passed
        def checkState(sha1, resp)
            st = getState(sha1, resp)
            return  st == "passed"  || st == "succeeded"
        end

        # Fetch validation organization builds JSON payload from Azure DevOps API.
        #
        # @return [Hash] JSON API response
        # @raise [MissingArgumentError] If validation organization is not configured
        # @raise [GitMaintainError] If API request fails
        def getBrValidJson()
            raise MissingArgumentError.new("validation organisation") if @valid_org == ''
            return getJson(@url + @valid_org + '/',
                           :azure_br_valid, @repo.name + '/_apis/build/builds?api-version=5.1')
        end

        # Fetch stable organization builds JSON payload from Azure DevOps API.
        #
        # @return [Hash] JSON API response
        # @raise [MissingArgumentError] If stable organization is not configured
        # @raise [GitMaintainError] If API request fails
        def getBrStableJson()
            raise MissingArgumentError.new("stable organisation") if @stable_org == ''
            return getJson(@url + @stable_org + '/',
             :azure_br_stable, @repo.name + '/_apis/build/builds?api-version=5.1')
        end

        # Find the specific Azure build matching the given commit SHA.
        #
        # @param sha1 [String] Commit SHA
        # @param resp [Hash] API response builds payload
        # @return [Hash, nil] Build dictionary, or nil if not found
        # @raise [GitMaintainError] If API response is missing expected commit keys
        def findBranch(sha1, resp)
            log(:DEBUG_CI, "Looking for build for #{sha1}")
            resp["value"].each(){|br|
                commit= br["sourceVersion"]
                raise GitMaintainError.new("Incomplete JSON received from Travis") if commit == nil
                log(:DEBUG_CI, "Found entry for sha #{commit}")
                next if commit != sha1
                return br
            }
            return nil
        end

        public
        # Retrieve the validation build state for a specific branch and commit.
        #
        # @param br [Branch] The Branch instance
        # @param sha1 [String] Commit SHA
        # @return [String] Build status string (e.g. 'succeeded')
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
        # @return [String] Build status string (e.g. 'succeeded')
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
        # @return [Boolean] True if build failed
        def isErrored(br, status)
            # https://docs.microsoft.com/en-us/rest/api/azure/devops/build/builds/list?
            # view=azure-devops-rest-5.1#buildresult
            return status == "failed"
        end
    end
end
