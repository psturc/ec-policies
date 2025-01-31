#
# METADATA
# description: |-
#   Enterprise Contract requires that each build was subjected
#   to a set of tests and that those tests all passed. This package
#   includes a set of rules to verify that.
#
#   The test result data must be reported by a Tekton Task that has been loaded
#   from an acceptable Tekton Bundle.
#   See xref:release_policy.adoc#attestation_task_bundle_package[Task bundle checks].
#
#   TODO: Document how you can skip the requirement for individual
#   tests if needed using the `non_blocking_rule` configuration.
#
package policy.release.test

import data.lib
import future.keywords.in

# METADATA
# title: No test data found
# description: |-
#   None of the tasks in the pipeline included a HACBS_TEST_OUTPUT
#   task result, which is where Enterprise Contract expects to find
#   test result data.
# custom:
#   short_name: test_data_missing
#   failure_msg: No test data found
#
deny[result] {
	count(lib.pipelinerun_attestations) > 0 # make sure we're looking at a PipelineRun attestation
	results := lib.results_from_tests
	count(results) == 0 # there are none at all

	result := lib.result_helper(rego.metadata.chain(), [])
}

# METADATA
# title: Test data is missing the results key
# description: |-
#   Each test result is expected to have a 'results' key. In at least
#   one of the HACBS_TEST_OUTPUT task results this key was not present.
# custom:
#   short_name: test_results_missing
#   failure_msg: Found tests without results
#
deny[result] {
	with_results := [result | result := lib.results_from_tests[_].value.result]
	count(with_results) != count(lib.results_from_tests)
	result := lib.result_helper(rego.metadata.chain(), [])
}

# METADATA
# title: Unsupported result in test data
# description: |-
#   This policy expects a set of known/supported results in the test data
#   It is a failure if we encounter a result that is not supported.
# custom:
#   short_name: test_result_unsupported
#   failure_msg: Test '%s' has unsupported result '%s'
#
deny[result] {
	all_unsupported := [u |
		result := lib.results_from_tests[_]
		test := result.value
		not test.result in lib.rule_data("supported_tests_results")
		u := {"task": result.name, "result": test.result}
	]

	count(all_unsupported) > 0
	unsupported = all_unsupported[_]
	result := lib.result_helper_with_term(
		rego.metadata.chain(),
		[unsupported.task, unsupported.result],
		unsupported.task,
	)
}

# METADATA
# title: Test result is FAILURE or ERROR
# description: |-
#   Enterprise Contract requires that all the tests in the test results
#   have a successful result. A successful result is one that isn't a
#   "FAILURE" or "ERROR". This will fail if any of the tests failed and
#   the failure message will list the names of the failing tests.
# custom:
#   short_name: test_result_failures
#   failure_msg: "Test %q did not complete successfully"
#
deny[result] {
	some test in resulted_in(lib.rule_data("failed_tests_results"))
	result := lib.result_helper_with_term(rego.metadata.chain(), [test], test)
}

# METADATA
# title: Test was skipped
# description: |-
#   Reports any test that has its result set to "SKIPPED".
# custom:
#   short_name: test_result_skipped
#   failure_msg: "Test %q was skipped"
#
warn[result] {
	some test in resulted_in(lib.rule_data("skipped_tests_results"))
	result := lib.result_helper_with_term(rego.metadata.chain(), [test], test)
}

# METADATA
# title: Test returned a warning
# description: |-
#   Reports any test that has its result set to "WARNING".
# custom:
#   short_name: test_result_warning
#   failure_msg: "Test %q returned a warning"
#
warn[result] {
	some test in resulted_in(lib.rule_data("warned_tests_results"))
	result := lib.result_helper_with_term(rego.metadata.chain(), [test], test)
}

resulted_in(results) = filtered_by_result {
	# Collect all tests that have resulted with one of the given
	# results and convert their name to "test:<name>" format
	filtered_by_result := {r |
		result := lib.results_from_tests[_]
		test := result.value
		test.result in results
		r := result.name
	}
}
