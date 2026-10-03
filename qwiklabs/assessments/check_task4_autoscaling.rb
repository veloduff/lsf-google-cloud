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

def check_task4_autoscaling(handles:, resources:, maximum_score:)
  compute = handles['project_0.ComputeV1']
  dns = handles['project_0.DnsV1']
  project_id = resources[:project_0][:project_id]
  zone = resources[:project_0][:default_zone] || 'us-central1-a'

  instances = compute.list_instances(project_id, zone)&.items || []
  worker_vms = instances.select { |i| i.name.start_with?('compute-') }
  rrsets = dns.list_resource_record_sets(project_id, 'lsf-internal-zone')&.rrsets || []
  worker_dns = rrsets.select { |r| r.name.start_with?('compute-') }

  if worker_vms.empty? && worker_dns.empty?
    return {
      score: 0,
      message: 'No dynamic compute-* worker VMs or DNS records found yet',
      student_message: 'burst_missing'
    }
  end

  {
    score: maximum_score,
    message: 'Task 4 dynamic cloud bursting verified',
    student_message: 'success'
  }
end
