package main

import (
	"fmt"
	"sync"

	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/cli-runtime/pkg/genericclioptions"
	"k8s.io/client-go/discovery"
	memcached "k8s.io/client-go/discovery/cached/memory"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/restmapper"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/kubectl/pkg/describe"
)

var (
	cfgCache sync.Map
	mapperCache sync.Map
	descCache sync.Map 
)

func gvrKey(ctx string, gvr schema.GroupVersionResource) string {
	return fmt.Sprintf("%s|%s/%s/%s", ctx, gvr.Group, gvr.Version, gvr.Resource)
}

func getRestConfig(ctx string) (*rest.Config, error) {
	if v, ok := cfgCache.Load(ctx); ok {
		return v.(*rest.Config), nil
	}

	loadingRules    := clientcmd.NewDefaultClientConfigLoadingRules()
	overrides       := &clientcmd.ConfigOverrides{CurrentContext: ctx}
	clientConfig    := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(loadingRules, overrides)
	cfg, err := clientConfig.ClientConfig()
	if err != nil {
		return nil, err
	}
	if v, dup := cfgCache.LoadOrStore(ctx, cfg); dup {
		return v.(*rest.Config), nil
	}
	return cfg, nil
}

func getMapper(cfg *rest.Config, ctx string, gvr schema.GroupVersionResource) (meta.RESTMapper, error) {
	key := gvrKey(ctx, gvr)
	if v, ok := mapperCache.Load(key); ok {
		return v.(meta.RESTMapper), nil
	}

	dc, err := discovery.NewDiscoveryClientForConfig(cfg)
	if err != nil {
		return nil, err
	}
	cached := memcached.NewMemCacheClient(dc)

	gr, err := restmapper.GetAPIGroupResources(cached)
	if err != nil {
		return nil, err
	}
	rm := restmapper.NewDiscoveryRESTMapper(gr)

	_, err = rm.KindFor(gvr) // force the GVR to be recognised
	if err != nil {
		return nil, err
	}

	if v, dup := mapperCache.LoadOrStore(key, rm); dup {
		return v.(meta.RESTMapper), nil
	}
	return rm, nil
}

func getDescriber(flags *genericclioptions.ConfigFlags, mapping *meta.RESTMapping, cacheKey string) (describe.ResourceDescriber, error) {
	if v, ok := descCache.Load(cacheKey); ok {
		return v.(describe.ResourceDescriber), nil
	}
	d, err := describe.Describer(flags, mapping)
	if err != nil {
		return nil, err
	}
	if v, dup := descCache.LoadOrStore(cacheKey, d); dup {
		return v.(describe.ResourceDescriber), nil
	}
	return d, nil
}
