package main

/*
#include <stdlib.h>
*/
import "C"

import (
    "bytes"
    "context"
    "fmt"
    "time"

    metav1   "k8s.io/apimachinery/pkg/apis/meta/v1"
    cmdutil  "k8s.io/kubectl/pkg/cmd/util"
    "k8s.io/kubectl/pkg/drain"
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/tools/clientcmd"
)

//export DrainNode
func DrainNode(
	cNodeName *C.char,
	cContext *C.char,
	cGrace C.int,
	cTimeout C.int,
	cIgnoreDS C.int,
	cDeleteEmptyDir C.int,
	cForce C.int,
	cDryRun C.int,
) *C.char {
	//------------------------------------------------------------//
	// 1.  Pull params off the C heap                             //
	//------------------------------------------------------------//
	nodeName := C.GoString(cNodeName)
	contextName := C.GoString(cContext)
	graceSeconds := int(cGrace)
	timeoutSeconds := int(cTimeout)
	ignoreDS := cIgnoreDS != 0
	deleteEmptyDir := cDeleteEmptyDir != 0
	force := cForce != 0
	dryRun := cDryRun != 0

	//------------------------------------------------------------//
	// 2.  Build client-go *rest.Config exactly once              //
	//------------------------------------------------------------//
	cfgOverrides := &clientcmd.ConfigOverrides{CurrentContext: contextName}
	loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
	cfg, err := clientcmd.
		NewNonInteractiveDeferredLoadingClientConfig(loadingRules, cfgOverrides).
		ClientConfig()
	if err != nil {
		return cString(fmt.Sprintf("error building rest.Config: %v", err))
	}

	clientset, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		return cString(fmt.Sprintf("error creating clientset: %v", err))
	}

	//------------------------------------------------------------//
	// 3.  Prepare the drain.Helper                               //
	//------------------------------------------------------------//
	var buf bytes.Buffer
	helper := drain.Helper{
		Ctx:                 context.TODO(),
		Client:              clientset,
		GracePeriodSeconds:  graceSeconds,
		Timeout:             time.Duration(timeoutSeconds) * time.Second,
		DeleteEmptyDirData:  deleteEmptyDir,
		IgnoreAllDaemonSets: ignoreDS,
		DisableEviction:     false,
		Force:               force,
		Out:                 &buf,
		ErrOut:              &buf,
	}

	if dryRun {
		helper.DryRunStrategy = cmdutil.DryRunServer
	}

	//------------------------------------------------------------//
	// 4.  Run the same sequence kubectl drain does               //
	//------------------------------------------------------------//
	//   4a. cordon first (if needed)

	nodeObj, err := clientset.CoreV1().
		Nodes().
		Get(context.TODO(), nodeName, metav1.GetOptions{})
	if err != nil {
		return cString(fmt.Sprintf("failed to get node %s: %v", nodeName, err))
	}

	if err := drain.RunCordonOrUncordon(&helper, nodeObj, true); err != nil {
		return cString(fmt.Sprintf("cordon failed: %v", err))
	}

	// if err := drain.RunCordonOrUncordon(&helper, nodeName, true); err != nil {
	// 	return cString(fmt.Sprintf("cordon failed: %v", err))
	// }

	//   4b. pick the pods to delete/evict
	pods, errs := helper.GetPodsForDeletion(nodeName)
	if len(errs) != 0 {
		return cString(fmt.Sprintf("pod pre-flight errors: %v", errs))
	}

	//   4c. evict / delete
	if err := helper.DeleteOrEvictPods(pods.Pods()); err != nil {
		return cString(fmt.Sprintf("drain failed: %v", err))
	}

	//   4d. success message (helper already wrote progress to buf)
	fmt.Fprintf(&buf, "Node %s drained successfully", nodeName)
	return cString(buf.String())
}
