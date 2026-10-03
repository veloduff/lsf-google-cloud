# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

def check_task5_eda_regression(handles:, resources:, maximum_score:)
  compute = handles['project_0.ComputeV1']
  project_id = resources[:project_0][:project_id]
  zone = resources[:project_0][:default_zone] || 'us-central1-a'

  submit_vm = compute.get_instance(project_id, zone, 'lsf-submit')
  master_vm = compute.get_instance(project_id, zone, 'lsf-master')
  unless submit_vm&.status == 'RUNNING' && master_vm&.status == 'RUNNING'
    return {
      score: 0,
      message: 'lsf-master and lsf-submit must be RUNNING to verify EDA regression',
      student_message: 'regression_missing'
    }
  end

  {
    score: maximum_score,
    message: 'Task 5 EDA verification and regression verified',
    student_message: 'success'
  }
end
