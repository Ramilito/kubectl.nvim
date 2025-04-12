package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"fmt"

	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/kubectl/pkg/describe"
)

func DescribeResource(
	cGroup *C.char,
	cVersion *C.char,
	cResource *C.char,
	cNamespace *C.char, 
	cName *C.char,
	cContext *C.char,
) *C.char {
	group := C.GoString(cGroup)
	version := C.GoString(cVersion)
	resource := C.GoString(cResource)
	namespace := C.GoString(cNamespace)
	name := C.GoString(cName)
	contextName := C.GoString(cContext)

	loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
	configOverrides := &clientcmd.ConfigOverrides{
		CurrentContext: contextName,
	}
	clientConfig := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(loadingRules, configOverrides)
	config, err := clientConfig.ClientConfig()
	if err != nil {
		return cString(fmt.Sprintf("Error building config: %v", err))
	}

	gvr := schema.GroupVersionResource{
		Group:    group,
		Version:  version,
		Resource: resource,
	}
	gvk := schema.GroupVersionKind{
		Group:   group,
		Version: version,
		Kind:    resource,
	}
	mapping := &meta.RESTMapping{
		Resource:         gvr,
		GroupVersionKind: gvk,
		Scope:            meta.RESTScopeNamespace,
	}

	d, ok := describe.GenericDescriberFor(mapping, config)
	if !ok || d == nil {
		return cString("GenericDescriberFor returned false (not supported).")
	}

	out, err := d.Describe(namespace, name, describe.DescriberSettings{ShowEvents: true})
	if err != nil {
		return cString(fmt.Sprintf("Error describing resource: %v", err))
	}
	return cString(out)
}

func main() {}

func cString(s string) *C.char {
	return C.CString(s)
}
