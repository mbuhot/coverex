defmodule CoverexTest do
	use ExUnit.Case

	alias Coverex.Task
	
	test "coveralls wished?" do
	  	opts = [coveralls: true]
	  	assert Task.post_to_coveralls?(opts) 
	end

	test "coveralls not wished?" do
	  	opts = [coveralls: false]
	  	refute Task.post_to_coveralls?(opts) 
	end

	test "is coveralls requested on the commandline?" do
		conf = Mix.Project.config()
		# IO.inspect conf
		assert Task.post_to_coveralls?(conf[:test_coverage])
	end

	test "positive check environment for travis" do
		env = %{"TRAVIS" => "true"}
		assert Task.running_travis?(env)
	end

	test "negative check environment for travis" do
		env = %{"TRAVIS" => "no"}
		refute Task.running_travis?(env)

		env = %{"TRAVIS" => "TRUE"}
		refute Task.running_travis?(env)
	end

	test "travis CI info with pull request" do
		env = %{
			"TRAVIS" => "true",
			"TRAVIS_JOB_ID" => "123",
			"TRAVIS_PULL_REQUEST" => "789"
		}
		assert Task.travis_ci_info(env) == %{
			service_name: "travis-ci",
			service_job_id: "123",
			service_pull_request: "789"
		}
	end

	test "travis CI info without pull request" do
		env = %{
			"TRAVIS" => "true",
			"TRAVIS_JOB_ID" => "123",
			"TRAVIS_PULL_REQUEST" => "false"
		}
		assert Task.travis_ci_info(env) == %{
			service_name: "travis-ci",
			service_job_id: "123"
		}
	end

	test "positive check environment for buildkite" do
		env = %{"BUILDKITE" => "true"}
		assert Task.running_buildkite?(env)
	end

	test "negative check environment for buildkite" do
		env = %{"BUILDKITE" => "no"}
		refute Task.running_buildkite?(env)

		env = %{"BUILDKITE" => "TRUE"}
		refute Task.running_buildkite?(env)
	end

	test "buildkite CI info with pull request" do
		env = %{
			"BUILDKITE" => "true",
			"BUILDKITE_BUILD_NUMBER" => "123",
			"BUILDKITE_JOB_ID" => "456",
			"BUILDKITE_BUILD_URL" => "url",
			"BUILDKITE_BRANCH" => "master",
			"BUILDKITE_PULL_REQUEST" => "789"
		}
		assert Task.buildkite_ci_info(env) == %{
			service_name: "buildkite",
			service_number: "123",
			service_job_id: "456",
			service_build_url: "url",
			service_branch: "master",
			service_pull_request: "789"
		}
	end

	test "buildkite CI info without pull request" do
		env = %{
			"BUILDKITE" => "true",
			"BUILDKITE_BUILD_NUMBER" => "123",
			"BUILDKITE_JOB_ID" => "456",
			"BUILDKITE_BUILD_URL" => "url",
			"BUILDKITE_BRANCH" => "master",
			"BUILDKITE_PULL_REQUEST" => "false"
		}
		assert Task.buildkite_ci_info(env) == %{
			service_name: "buildkite",
			service_number: "123",
			service_job_id: "456",
			service_build_url: "url",
			service_branch: "master"
		}
	end

	# test "post to whatever" do
	# 	conf = Mix.Project.config()
	# 	assert nil != conf[:test_coverage], "requires to run under `test --cover` "

	# 	assert :ok = Task.post_coveralls([Coverex.Task], ".", "id-123", "http://pastebin.com")
	# end
end
