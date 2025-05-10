package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"fmt"

	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/cli-runtime/pkg/genericclioptions"
	"k8s.io/client-go/discovery"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/restmapper"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/kubectl/pkg/describe"
)

//export DescribeResource
func DescribeResource(
	cGroup    *C.char,
	cVersion  *C.char,
	cResource *C.char,
	cNamespace *C.char,
	cName     *C.char,
	cContext  *C.char,
) *C.char {
	// ------------ 1.  Pull parameters off the C heap ----------------
	group      := C.GoString(cGroup)
	version    := C.GoString(cVersion)
	resource   := C.GoString(cResource)
	namespace  := C.GoString(cNamespace)
	name       := C.GoString(cName)
	contextName:= C.GoString(cContext)

	// ------------ 2.  Build a *rest.Config exactly once -------------
	loadingRules     := clientcmd.NewDefaultClientConfigLoadingRules()
	configOverrides  := &clientcmd.ConfigOverrides{CurrentContext: contextName}
	clientConfig     := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(loadingRules, configOverrides)
	cfg, err := clientConfig.ClientConfig()
	if err != nil {
		return cString(fmt.Sprintf("Error building rest.Config: %v", err))
	}

	// ------------ 3.  Create the kubectl factory (ConfigFlags) ------
	flags := genericclioptions.NewConfigFlags(false) // don't add klog flags
	flags.WrapConfigFn = func(*rest.Config) *rest.Config { return cfg }
	flags.Namespace    = &namespace // keep user's namespace from C
	flags.Context      = &contextName

	// ------------ 4.  Produce a RESTMapping (cheap discovery) -------
	// First try full discovery (nice when the cluster is reachable)
	var mapping *meta.RESTMapping
	dc, derr := discovery.NewDiscoveryClientForConfig(cfg)
	if derr == nil {
		gr, err := restmapper.GetAPIGroupResources(dc)
		if err == nil {
			rm := restmapper.NewDiscoveryRESTMapper(gr)
			gvk, err := rm.KindFor(schema.GroupVersionResource{
				Group:    group,
				Version:  version,
				Resource: resource,
			})
			if err == nil {
				mapping, _ = rm.RESTMapping(gvk.GroupKind(), gvk.Version)
			}
		}
	}

	// Fallback: manual mapping (works even if discovery fails/offline)
	if mapping == nil {
		mapping = &meta.RESTMapping{
			Resource: schema.GroupVersionResource{Group: group, Version: version, Resource: resource},
			GroupVersionKind: schema.GroupVersionKind{Group: group, Version: version, Kind: resource},
			Scope: meta.RESTScopeNamespace, // cluster-scoped? adjust if needed
		}
	}

	// ------------ 5.  Ask kubectl for the right describer -----------
	d, err := describe.Describer(flags, mapping)
	if err != nil || d == nil {
		return cString(fmt.Sprintf("Unable to find describer for %s: %v", resource, err))
	}

	// ------------ 6.  Do the actual describe and hand it back -------
	out, err := d.Describe(namespace, name, describe.DescriberSettings{ShowEvents: true})
	if err != nil {
		return cString(fmt.Sprintf("Error describing %s/%s: %v", resource, name, err))
	}
	return cString(out)
}
