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

def check_task2_golden_image(handles:, resources:, maximum_score:)
  compute = handles['project_0.ComputeV1']
  project_id = resources[:project_0][:project_id]

  images = compute.list_images(project_id)&.items || []
  golden = images.find { |img| img.name == 'lsf-submit-and-worker-rocky-8-image' && img.status == 'READY' }
  unless golden
    return {
      score: 0,
      message: 'Golden image lsf-submit-and-worker-rocky-8-image not found or not READY',
      student_message: 'image_missing'
    }
  end

  {
    score: maximum_score,
    message: 'Task 2 Golden Image verified READY',
    student_message: 'success'
  }
end
