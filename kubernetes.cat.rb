name 'Kubernetes Cluster'
rs_ca_ver 20131202
short_description 'Creates a Kubernetes cluster'

parameter "node_count" do
  type "number"
  label "Node Count"
  category "Cluster"
  description "Number of cluster nodes. Does not include master node."
  default 3
  min_value 1
  max_value 99
end

resource 'kube_master', type: 'server' do
  name 'kube-master'
  cloud 'Google'
  datacenter 'us-central1-b'
  instance_type 'n1-standard-1'
  security_groups 'allow-adam'
  server_template find('Kubernetes', revision: 0)
  inputs do {
    'ENABLE_AUTO_UPGRADE' => 'text:true',
    'KUBE_ROLE' => 'text:master',
    'MONITORING_METHOD' => 'text:auto',
    'MY_IP' => 'env:PRIVATE_IP',
    'SERVER_NAME' => 'env:RS_SERVER_NAME',
    'UPGRADES_FILE_LOCATION' => 'text:https://rightlink.rightscale.com/rightlink/upgrades',
  } end
end

resource 'kube_node', type: 'server_array' do
  name 'kube-node'
  cloud 'Google'
  datacenter 'us-central1-b'
  instance_type 'n1-standard-1'
  security_groups 'allow-adam'
  server_template find('Kubernetes', revision: 0)
  inputs do {
    'ENABLE_AUTO_UPGRADE' => 'text:true',
    'KUBE_ROLE' => 'text:node',
    'MONITORING_METHOD' => 'text:auto',
    'MY_IP' => 'env:PRIVATE_IP',
    'SERVER_NAME' => 'env:RS_SERVER_NAME',
    'UPGRADES_FILE_LOCATION' => 'text:https://rightlink.rightscale.com/rightlink/upgrades',
  } end
  state 'disabled'
  array_type 'alert'
  elasticity_params do {
    'bounds' => {
      'min_count'            => $node_count,
      'max_count'            => $node_count
    },
    'pacing' => {
      'resize_calm_time'     => 5,
      'resize_down_by'       => 1,
      'resize_up_by'         => 1
    },
    'alert_specific_params' => {
      'decision_threshold'   => 51,
      'voters_tag_predicate' => 'Kubernetes'
    }
  } end
end

operation 'launch' do
  description 'Launch the application'
  definition 'launch'
end

operation 'enable' do
  description 'Enable the application'
  definition 'enable'
end

define launch(@kube_master, @kube_node) return @kube_master, @kube_node do
  call sys_get_execution_id() retrieve $execution_id

  @@deployment.multi_update_inputs(inputs: {
    'KUBE_CLUSTER':'text:' + $execution_id,
    'KUBE_RELEASE_TAG':'text:v1.3.0-alpha.2',
    'FLANNEL_VERSION':'text:0.5.5'
  })

  concurrent return @kube_master, @kube_node do
    provision(@kube_master)
    provision(@kube_node)
  end
end

define enable(@kube_master, @kube_node) return @kube_master, @kube_node do
  sub task_name:"Setting up Kubernetes master" do
    $options = { rightscript: { name: 'KUBE Launch Cluster' } }
    call run_executable(@kube_master, $options)
  end
  sub task_name:"Setting up Kubernetes nodes" do
    $options = { rightscript: { name: 'KUBE Launch Cluster' } }
    call run_executable(@kube_node.current_instances(), $options)
  end
end

# Returns all tags for a specified resource. Assumes that only one resource
# is passed in, and will return tags for only the first resource in the collection.
#
# @param @resource [ResourceCollection] a ResourceCollection containing only a
#   single resource for which to return tags
#
# @return $tags [Array<String>] an array of tags assigned to @resource
define get_tags_for_resource(@resource) return $tags do
  $tags = []
  $tags_response = rs.tags.by_resource(resource_hrefs: [@resource.href])
  $inner_tags_ary = first(first($tags_response))["tags"]
  $tags = map $current_tag in $inner_tags_ary return $tag do
    $tag = $current_tag["name"]
  end
  $tags = $tags
end

# Fetches the execution id of "this" cloud app using the default tags set on a
# deployment created by SS.
# selfservice:href=/api/manager/projects/12345/executions/54354bd284adb8871600200e
#
# @return [String] The execution ID of the current cloud app
define sys_get_execution_id() return $execution_id do
  call get_tags_for_resource(@@deployment) retrieve $tags_on_deployment
  $href_tag = map $current_tag in $tags_on_deployment return $tag do
    if $current_tag =~ "(selfservice:href)"
      $tag = $current_tag
    end
  end

  if type($href_tag) == "array" && size($href_tag) > 0
    $tag_split_by_value_delimiter = split(first($href_tag), "=")
    $tag_value = last($tag_split_by_value_delimiter)
    $value_split_by_slashes = split($tag_value, "/")
    $execution_id = last($value_split_by_slashes)
  else
    $execution_id = "N/A"
  end
end

# Return a rightscript href (or null) if it was found in the runnable bindings
# of the supplied ServerTemlate
#
# @param @server_template [ServerTemplateResourceCollection] a collection
#   containing exactly one ServerTemplate to search for the specified RightScript
# @param $name [String] the string name of the RightScript to return
# @param $options [Hash] a hash of options where the possible keys are;
#   * runlist [String] one of (boot|operational|decommission).  When supplied
#     the search will be restricted to the supplied runlist, otherwise all
#     runnable bindings will be evaulated, and the first result will be returned
#
# @return $href [String] the href of the first RightScript found (or null)
#
# @raise a string error message if the @server_template parameter contains more
#   than one (1) ServerTemplate
define server_template_get_rightscript_from_runnable_bindings(@server_template, $name, $options) return $href do
  if size(@server_template) != 1
    raise "server_template_get_rightscript_from_runnable_bindings() expects exactly one ServerTemplate in the @server_template parameter.  Got "+size(@server_template)
  end
  $href = null
  $select_hash = {"right_script": {"name": $name}}
  if contains?(keys($options),["runlist"])
    $select_hash["sequence"] = $options["runlist"]
  end
  @right_scripts = select(@server_template.runnable_bindings(), $select_hash)
  if size(@right_scripts) > 0
    $href = @right_scripts.right_script().href
  end
end

# Does some validation and gets the server template for an instance
#
# @param @instance [InstanceResourceCollection] the instance for which to get
#   the server template
#
# @return [ServerTemplateReourceCollection] The server template for the @instance
#
# @raise a string error message if the @instance parameter is not an instance
#   collection
# @raise a string error message if the @instance does not have a server_template
#   rel
define instance_get_server_template(@instance) return @server_template do
  $type = to_s(@instance)
  if !($type =~ "instance")
    raise "instance_get_server_template requires @instance to be of type rs.instances.  Got "+$type+" instead"
  end
  $stref = select(@instance.links, {"rel": "server_template"})
  if size($stref) == 0
    raise "instance_get_server_template can't get the ServerTemplate of an instance which does not have a server_template rel."
  end
  @server_template = @instance.server_template()
end

# Run a rightscript or recipe on a server or instance collection.
#
# @param @target [ServerResourceCollection|InstanceResourceCollection] the
#   resource collection to run the executable on.
# @param $options [Hash] a hash of options where the possible keys are;
#   * ignore_lock [Bool] whether to run the executable even when the instance
#     is locked.  Default: false
#   * wait_for_completion [Bool] Whether this definition should block waiting for
#     the executable to finish running or fail.  Default: true
#   * inputs [Hash] the inputs to pass to the run_executable request.  Default: {}
#   * rightscript [Hash] a hash of rightscript details where the possible keys are;
#     * name [String] the name of the rightscript to execute
#     * revision [Int] the revision number of the rightscript to run.
#       If not supplied the "latest" (which could be HEAD) will be used.
#     * href [String] if specified href takes prescedence and defines the *exact*
#       rightscript and revision to execute
#     * revmatch [String] a ServerTemplate runlist name (one of "boot",
#       "operational","decomission").  When supplied only the "name" option
#       is considered and is required.  The RightScript which is executed will
#       be the one with the same name that is in the specified runlist.
#   * recipe [String] the recipe name to execute (must be associated with the
#     @target's ServerTemplate)
#
# @return @task [TaskResourceCollection] the task returned by the run_executable
#   request
#
# @see http://reference.rightscale.com/api1.5/resources/ResourceInstances.html#multi_run_executable
# @see http://reference.rightscale.com/api1.5/resources/ResourceTasks.html
define run_executable(@target,$options) return @tasks do
  @tasks = rs.tasks.empty()
  $default_options = {
    ignore_lock: false,
    wait_for_completion: true,
    inputs: {}
  }

  $merged_options = $options + $default_options

  @instances = rs.instances.empty()
  $target_type = type(@target)
  if $target_type == "rs.servers"
    @instances = @target.current_instance()
  elsif $target_type == "rs.instances"
    @instances = @target
  else
    raise "run_executable() can not operate on a collection of type "+$target_type
  end

  $run_executable_params_hash = {inputs: $merged_options["inputs"]}
  if contains?(keys($merged_options),["rightscript"])
    if contains?(keys($merged_options["rightscript"]),["revmatch"])
      if !contains?(keys($merged_options["rightscript"]),["name"])
        raise "run_executable() requires both 'name' and 'revmatch' when specifying 'revmatch'"
      end
      call instance_get_server_template(@instances) retrieve @server_template
      call server_template_get_rightscript_from_runnable_bindings(@server_template, $merged_options["rightscript"]["name"], {runlist: $merged_options["rightscript"]["revmatch"]}) retrieve $script_href
      if !$script_href
        raise "run_executable() unable to find RightScript named "+$merged_options["rightscript"]["name"]+" in the "+$merged_options["rightscript"]["revmatch"]+" runlist of the ServerTempate "+@server_template.name
      end
      $run_executable_params_hash["right_script_href"] = $script_href
    elsif any?(keys($merged_options["rightscript"]),"/(name|href)/")
      if contains?(keys($merged_options["rightscript"]),["href"])
        $run_executable_params_hash["right_script_href"] = $merged_options["rightscript"]["href"]
      else
        @scripts = rs.right_scripts.get(filter: ["name=="+$merged_options["rightscript"]["name"]])
        if empty?(@scripts)
          raise "run_executable() unable to find RightScript with the name "+$merged_options["rightscript"]["name"]
        end
        $revision = 0
        if contains?(keys($merged_options["rightscript"]),["revision"])
          $revision = $merged_options["rightscript"]["revision"]
        end
        $revisions, @script_to_run = concurrent map @script in @scripts return $available_revision,@script_with_revision do
          $available_revision = @script.revision
          if $available_revision == $revision
            @script_with_revision = @script
          else
            # TODO: This won't be necessary when RCL assigns the proper empty return
            # collection type.
            @script_with_revision = rs.right_scripts.empty()
          end
        end
        if empty?(@script_to_run)
          raise "run_executable() found the script named "+$merged_options["rightscript"]["name"]+" but revision "+$revision+" was not found.  Available revisions are "+to_s($revisions)
        end
        $run_executable_params_hash["right_script_href"] = @script_to_run.href
      end
    else
      raise "run_executable() requires either 'name' or 'href' when executing a RightScript.  Found neither."
    end
  elsif contains?(keys($merged_options),["recipe"])
    $run_executable_params_hash["recipe_name"] = $merged_options["recipe"]
  else
    raise "run_executable() requires either 'rightscript' or 'recipe' in the $options.  Found neither."
  end

  @tasks = @instances.run_executable($run_executable_params_hash)

  if $merged_options["wait_for_completion"]
    sleep_until(all?(@tasks.summary[], "/^(completed|failed|aborted)/i"))
    if any?(@tasks.summary[], "/failed|aborted/i")
      raise "Failed to run " + to_s($run_executable_params_hash)
    end
  end
end
