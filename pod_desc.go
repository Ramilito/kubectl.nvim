func describeContainers(label string, containers []corev1.Container, containerStatuses []corev1.ContainerStatus,
	resolverFn EnvVarResolverFunc, w PrefixWriter, space string) {
	statuses := map[string]corev1.ContainerStatus{}
	for _, status := range containerStatuses {
		statuses[status.Name] = status
	}

	describeContainersLabel(containers, label, space, w)

	for _, container := range containers {
		status, ok := statuses[container.Name]
		describeContainerBasicInfo(container, status, ok, space, w)
		describeContainerCommand(container, w)
		if ok {
			describeContainerState(status, w)
		}
		describeResources(&container.Resources, w, LEVEL_2)
		describeContainerProbe(container, w)
		if len(container.EnvFrom) > 0 {
			describeContainerEnvFrom(container, resolverFn, w)
		}
		describeContainerEnvVars(container, resolverFn, w)
		describeContainerVolumes(container, w)
	}
}

func printAnnotationsMultiline(w PrefixWriter, title string, annotations map[string]string) {
	w.Write(LEVEL_0, "%s:\t", title)

	// to print labels in the sorted order
	keys := make([]string, 0, len(annotations))
	for key := range annotations {
		if skipAnnotations.Has(key) {
			continue
		}
		keys = append(keys, key)
	}
	if len(keys) == 0 {
		w.WriteLine("<none>")
		return
	}
	sort.Strings(keys)
	indent := "\t"
	for i, key := range keys {
		if i != 0 {
			w.Write(LEVEL_0, indent)
		}
		value := strings.TrimSuffix(annotations[key], "\n")
		if (len(value)+len(key)+2) > maxAnnotationLen || strings.Contains(value, "\n") {
			w.Write(LEVEL_0, "%s:\n", key)
			for _, s := range strings.Split(value, "\n") {
				w.Write(LEVEL_0, "%s  %s\n", indent, shorten(s, maxAnnotationLen-2))
			}
		} else {
			w.Write(LEVEL_0, "%s: %s\n", key, value)
		}
	}
}


func describeResources(resources *corev1.ResourceRequirements, w PrefixWriter, level int) {
	if resources == nil {
		return
	}

	if len(resources.Limits) > 0 {
		w.Write(level, "Limits:\n")
	}
	for _, name := range SortedResourceNames(resources.Limits) {
		quantity := resources.Limits[name]
		w.Write(level+1, "%s:\t%s\n", name, quantity.String())
	}

	if len(resources.Requests) > 0 {
		w.Write(level, "Requests:\n")
	}
	for _, name := range SortedResourceNames(resources.Requests) {
		quantity := resources.Requests[name]
		w.Write(level+1, "%s:\t%s\n", name, quantity.String())
	}
}

// printLabelsMultiline prints multiple labels with a user-defined alignment.
func printNodeSelectorTermsMultilineWithIndent(w PrefixWriter, indentLevel int, title, innerIndent string, reqs []corev1.NodeSelectorRequirement) {
	w.Write(indentLevel, "%s:%s", title, innerIndent)

	if len(reqs) == 0 {
		w.WriteLine("<none>")
		return
	}

	for i, req := range reqs {
		if i != 0 {
			w.Write(indentLevel, "%s", innerIndent)
		}
		exprStr := fmt.Sprintf("%s %s", req.Key, strings.ToLower(string(req.Operator)))
		if len(req.Values) > 0 {
			exprStr = fmt.Sprintf("%s [%s]", exprStr, strings.Join(req.Values, ", "))
		}
		w.Write(LEVEL_0, "%s\n", exprStr)
	}
}

func printController(controllee metav1.Object) string {
	if controllerRef := metav1.GetControllerOf(controllee); controllerRef != nil {
		return fmt.Sprintf("%s/%s", controllerRef.Kind, controllerRef.Name)
	}
	return ""
}

func describePodIPs(pod *corev1.Pod, w PrefixWriter, space string) {
	if len(pod.Status.PodIPs) == 0 {
		w.Write(LEVEL_0, "%sIPs:\t<none>\n", space)
		return
	}
	w.Write(LEVEL_0, "%sIPs:\n", space)
	for _, ipInfo := range pod.Status.PodIPs {
		w.Write(LEVEL_1, "IP:\t%s\n", ipInfo.IP)
	}
}


func describePod(pod *corev1.Pod, events *corev1.EventList) (string, error) {
	return tabbedString(func(out io.Writer) error {
		w := NewPrefixWriter(out)
		w.Write(LEVEL_0, "Name:\t%s\n", pod.Name)
		w.Write(LEVEL_0, "Namespace:\t%s\n", pod.Namespace)
		if pod.Spec.Priority != nil {
			w.Write(LEVEL_0, "Priority:\t%d\n", *pod.Spec.Priority)
		}
		if len(pod.Spec.PriorityClassName) > 0 {
			w.Write(LEVEL_0, "Priority Class Name:\t%s\n", pod.Spec.PriorityClassName)
		}
		if pod.Spec.RuntimeClassName != nil && len(*pod.Spec.RuntimeClassName) > 0 {
			w.Write(LEVEL_0, "Runtime Class Name:\t%s\n", *pod.Spec.RuntimeClassName)
		}
		if len(pod.Spec.ServiceAccountName) > 0 {
			w.Write(LEVEL_0, "Service Account:\t%s\n", pod.Spec.ServiceAccountName)
		}
		if pod.Spec.NodeName == "" {
			w.Write(LEVEL_0, "Node:\t<none>\n")
		} else {
			w.Write(LEVEL_0, "Node:\t%s\n", pod.Spec.NodeName+"/"+pod.Status.HostIP)
		}
		if pod.Status.StartTime != nil {
			w.Write(LEVEL_0, "Start Time:\t%s\n", pod.Status.StartTime.Time.Format(time.RFC1123Z))
		}
		printLabelsMultiline(w, "Labels", pod.Labels)
		printAnnotationsMultiline(w, "Annotations", pod.Annotations)
		if pod.DeletionTimestamp != nil && pod.Status.Phase != corev1.PodFailed && pod.Status.Phase != corev1.PodSucceeded {
			w.Write(LEVEL_0, "Status:\tTerminating (lasts %s)\n", translateTimestampSince(*pod.DeletionTimestamp))
			w.Write(LEVEL_0, "Termination Grace Period:\t%ds\n", *pod.DeletionGracePeriodSeconds)
		} else {
			w.Write(LEVEL_0, "Status:\t%s\n", string(pod.Status.Phase))
		}
		if len(pod.Status.Reason) > 0 {
			w.Write(LEVEL_0, "Reason:\t%s\n", pod.Status.Reason)
		}
		if len(pod.Status.Message) > 0 {
			w.Write(LEVEL_0, "Message:\t%s\n", pod.Status.Message)
		}
		if pod.Spec.SecurityContext != nil && pod.Spec.SecurityContext.SeccompProfile != nil {
			w.Write(LEVEL_0, "SeccompProfile:\t%s\n", pod.Spec.SecurityContext.SeccompProfile.Type)
			if pod.Spec.SecurityContext.SeccompProfile.Type == corev1.SeccompProfileTypeLocalhost {
				w.Write(LEVEL_0, "LocalhostProfile:\t%s\n", *pod.Spec.SecurityContext.SeccompProfile.LocalhostProfile)
			}
		}
		// remove when .IP field is deprecated
		w.Write(LEVEL_0, "IP:\t%s\n", pod.Status.PodIP)
		describePodIPs(pod, w, "")
		if controlledBy := printController(pod); len(controlledBy) > 0 {
			w.Write(LEVEL_0, "Controlled By:\t%s\n", controlledBy)
		}
		if len(pod.Status.NominatedNodeName) > 0 {
			w.Write(LEVEL_0, "NominatedNodeName:\t%s\n", pod.Status.NominatedNodeName)
		}

		if pod.Spec.Resources != nil {
			w.Write(LEVEL_0, "Resources:\n")
			describeResources(pod.Spec.Resources, w, LEVEL_1)
		}

		if len(pod.Spec.InitContainers) > 0 {
			describeContainers("Init Containers", pod.Spec.InitContainers, pod.Status.InitContainerStatuses, EnvValueRetriever(pod), w, "")
		}
		describeContainers("Containers", pod.Spec.Containers, pod.Status.ContainerStatuses, EnvValueRetriever(pod), w, "")
		if len(pod.Spec.EphemeralContainers) > 0 {
			var ec []corev1.Container
			for i := range pod.Spec.EphemeralContainers {
				ec = append(ec, corev1.Container(pod.Spec.EphemeralContainers[i].EphemeralContainerCommon))
			}
			describeContainers("Ephemeral Containers", ec, pod.Status.EphemeralContainerStatuses, EnvValueRetriever(pod), w, "")
		}
		if len(pod.Spec.ReadinessGates) > 0 {
			w.Write(LEVEL_0, "Readiness Gates:\n  Type\tStatus\n")
			for _, g := range pod.Spec.ReadinessGates {
				status := "<none>"
				for _, c := range pod.Status.Conditions {
					if c.Type == g.ConditionType {
						status = fmt.Sprintf("%v", c.Status)
						break
					}
				}
				w.Write(LEVEL_1, "%v \t%v \n",
					g.ConditionType,
					status)
			}
		}
		if len(pod.Status.Conditions) > 0 {
			w.Write(LEVEL_0, "Conditions:\n  Type\tStatus\n")
			for _, c := range pod.Status.Conditions {
				w.Write(LEVEL_1, "%v \t%v \n",
					c.Type,
					c.Status)
			}
		}
		describeVolumes(pod.Spec.Volumes, w, "")
		w.Write(LEVEL_0, "QoS Class:\t%s\n", qos.GetPodQOS(pod))
		printLabelsMultiline(w, "Node-Selectors", pod.Spec.NodeSelector)
		printPodTolerationsMultiline(w, "Tolerations", pod.Spec.Tolerations)
		describeTopologySpreadConstraints(pod.Spec.TopologySpreadConstraints, w, "")
		if events != nil {
			DescribeEvents(events, w)
		}
		return nil
	})
}
