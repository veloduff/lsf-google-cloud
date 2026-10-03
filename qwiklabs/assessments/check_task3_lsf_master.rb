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

def check_task3_lsf_master(handles:, resources:, maximum_score:)
  storage = handles['project_0.StorageV1']
  compute = handles['project_0.ComputeV1']
  project_id = resources[:project_0][:project_id]
  zone = resources[:project_0][:default_zone] || 'us-central1-a'
  bucket_name = "lsf-install-bucket-#{project_id}"

  objects = storage.list_objects(bucket_name)&.items&.map(&:name) || []
  required_archives = [
    'lsf10.1_linux2.6-glibc2.3-x86_64.tar.Z',
    'lsf10.1_linux2.6-glibc2.3-x86_64-601088.tar.Z',
    'lsf10.1_lsfinstall_linux_x86_64.tar.Z',
    'lsf_std_entitlement.dat'
  ]
  missing = required_archives - objects
  unless missing.empty?
    return {
      score: 0,
      message: "Missing LSF archives in #{bucket_name}: #{missing.inspect}",
      student_message: 'archives_missing'
    }
  end

  master = compute.get_instance(project_id, zone, 'lsf-master')
  unless master && master.status == 'RUNNING'
    return {
      score: 10,
      message: 'lsf-master instance is not running',
      student_message: 'master_not_ready'
    }
  end

  {
    score: maximum_score,
    message: 'Task 3 LSF archives and lsf-master verified',
    student_message: 'success'
  }
end
