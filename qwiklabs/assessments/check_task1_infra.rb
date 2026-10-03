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

def check_task1_infra(handles:, resources:, maximum_score:)
  compute = handles['project_0.ComputeV1']
  storage = handles['project_0.StorageV1']
  dns = handles['project_0.DnsV1']
  project_id = resources[:project_0][:project_id]
  zone = resources[:project_0][:default_zone] || 'us-central1-a'

  networks = compute.list_networks(project_id)&.items&.map(&:name) || []
  unless networks.include?('onprem-vpc') && networks.include?('gcp-burst-vpc')
    return {
      score: 0,
      message: "Missing VPCs: found #{networks.inspect}",
      student_message: 'vpc_missing'
    }
  end

  buckets = storage.list_buckets(project_id)&.items&.map(&:name) || []
  unless buckets.include?("lsf-install-bucket-#{project_id}")
    return {
      score: 5,
      message: "Missing GCS bucket lsf-install-bucket-#{project_id}",
      student_message: 'bucket_missing'
    }
  end

  zones = dns.list_managed_zones(project_id)&.managed_zones&.map(&:name) || []
  unless zones.include?('lsf-internal-zone')
    return {
      score: 10,
      message: 'Missing Cloud DNS private zone lsf-internal-zone',
      student_message: 'dns_missing'
    }
  end

  instances = compute.list_instances(project_id, zone)&.items || []
  running_names = instances.select { |i| i.status == 'RUNNING' }.map(&:name)
  unless running_names.include?('lsf-master') && running_names.include?('lsf-submit')
    return {
      score: 15,
      message: "VMs not running: #{running_names.inspect}",
      student_message: 'vms_missing'
    }
  end

  {
    score: maximum_score,
    message: 'Task 1 hybrid infrastructure verified',
    student_message: 'success'
  }
end
