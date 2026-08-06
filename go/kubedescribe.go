package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"errors"
	"fmt"
	"path/filepath"

	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/discovery"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/kubectl/pkg/describe"
)

func buildRestConfig(kubeconfig, context string) (*rest.Config, error) {
	var rules *clientcmd.ClientConfigLoadingRules
	if kubeconfig != "" {
		rules = &clientcmd.ClientConfigLoadingRules{Precedence: filepath.SplitList(kubeconfig)}
	} else {
		// NOT NewDefaultClientConfigLoadingRules(): that reads the stale
		// process-start KUBECONFIG snapshot (Go never sees the host's setenv).
		rules = &clientcmd.ClientConfigLoadingRules{Precedence: []string{clientcmd.RecommendedHomeFile}}
	}
	overrides := &clientcmd.ConfigOverrides{CurrentContext: context}
	return clientcmd.NewNonInteractiveDeferredLoadingClientConfig(rules, overrides).ClientConfig()
}

type restConfigGetter struct{ cfg *rest.Config }

func (g *restConfigGetter) ToRESTConfig() (*rest.Config, error) { return g.cfg, nil }
func (g *restConfigGetter) ToDiscoveryClient() (discovery.CachedDiscoveryInterface, error) {
	return nil, errors.New("not supported")
}
func (g *restConfigGetter) ToRESTMapper() (meta.RESTMapper, error) {
	return nil, errors.New("not supported")
}
func (g *restConfigGetter) ToRawKubeConfigLoader() clientcmd.ClientConfig { return nil }

//export DescribeResource
func DescribeResource(
	cGroup, cVersion, cKind, cResource, cNamespace, cName, cContext, cKubeconfig *C.char,
) *C.char {
	group := C.GoString(cGroup)
	version := C.GoString(cVersion)
	kind := C.GoString(cKind)
	resource := C.GoString(cResource)
	namespace := C.GoString(cNamespace)
	name := C.GoString(cName)
	ctxName := C.GoString(cContext)
	kubeconfig := C.GoString(cKubeconfig)

	if kind == "" {
		kind = resource
	}
	if resource == "" {
		resource = kind
	}

	cfg, err := buildRestConfig(kubeconfig, ctxName)
	if err != nil {
		return cString(fmt.Sprintf("Error building rest.Config: %v", err))
	}

	gvr := schema.GroupVersionResource{Group: group, Version: version, Resource: resource}
	scope := meta.RESTScope(meta.RESTScopeRoot)
	if namespace != "" {
		scope = meta.RESTScopeNamespace
	}
	mapping := &meta.RESTMapping{
		Resource:         gvr,
		GroupVersionKind: schema.GroupVersionKind{Group: group, Version: version, Kind: kind},
		Scope:            scope,
	}

	d, err := describe.Describer(&restConfigGetter{cfg: cfg}, mapping)
	if err != nil || d == nil {
		return cString(fmt.Sprintf("Unable to find describer for %s: %v", resource, err))
	}

	out, err := d.Describe(namespace, name, describe.DescriberSettings{ShowEvents: true})
	if err != nil {
		return cString(fmt.Sprintf("Error describing %s/%s: %v", resource, name, err))
	}
	return cString(out)
}
