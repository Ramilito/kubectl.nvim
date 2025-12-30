package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"crypto/sha256"
	"encoding/hex"
	"sync"
	"sync/atomic"
	"time"

	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/cli-runtime/pkg/genericclioptions"
	"k8s.io/client-go/rest"
	"k8s.io/kubectl/pkg/describe"
)

// Session management
var (
	sessionCounter uint64
	sessions       sync.Map // map[uint64]*describeSession
)

const (
	defaultRefreshRate    = 5 * time.Second
	maxRetryInterval      = 2 * time.Minute
	outputChannelCapacity = 1
)

type describeSession struct {
	id        uint64
	namespace string
	name      string
	context   string
	gvr       schema.GroupVersionResource

	describer describe.ResourceDescriber
	flags     *genericclioptions.ConfigFlags

	outputCh   chan string
	closed     atomic.Bool
	lastHash   string
	hashMu     sync.Mutex
	closeCh    chan struct{}
}

func newDescribeSession(
	group, version, resource, namespace, name, context string,
) (*describeSession, string) {
	cfg, err := getRestConfig(context)
	if err != nil {
		return nil, "Error building rest.Config: " + err.Error()
	}

	flags := genericclioptions.NewConfigFlags(false)
	flags.WrapConfigFn = func(*rest.Config) *rest.Config { return cfg }
	flags.Namespace = &namespace
	flags.Context = &context

	gvr := schema.GroupVersionResource{Group: group, Version: version, Resource: resource}
	rm, err := getMapper(cfg, context, gvr)
	var mapping *meta.RESTMapping
	if err == nil {
		if gvk, kerr := rm.KindFor(gvr); kerr == nil {
			mapping, _ = rm.RESTMapping(gvk.GroupKind(), gvk.Version)
		}
	}
	if mapping == nil {
		mapping = &meta.RESTMapping{
			Resource:         gvr,
			GroupVersionKind: schema.GroupVersionKind{Group: group, Version: version, Kind: resource},
			Scope:            meta.RESTScopeNamespace,
		}
	}

	cacheKey := gvrKey(context, gvr)
	d, err := getDescriber(flags, mapping, cacheKey)
	if err != nil || d == nil {
		return nil, "Unable to find describer: " + err.Error()
	}

	id := atomic.AddUint64(&sessionCounter, 1)
	session := &describeSession{
		id:        id,
		namespace: namespace,
		name:      name,
		context:   context,
		gvr:       gvr,
		describer: d,
		flags:     flags,
		outputCh:  make(chan string, outputChannelCapacity),
		closeCh:   make(chan struct{}),
	}

	// Do initial describe
	output, err := d.Describe(namespace, name, describe.DescriberSettings{ShowEvents: true})
	if err != nil {
		return nil, "Error describing resource: " + err.Error()
	}

	session.lastHash = hashString(output)

	// Send initial output
	select {
	case session.outputCh <- output:
	default:
	}

	// Start polling goroutine
	go session.pollLoop()

	sessions.Store(id, session)
	return session, ""
}

func (s *describeSession) pollLoop() {
	delay := defaultRefreshRate
	backoff := defaultRefreshRate

	for {
		select {
		case <-s.closeCh:
			return
		case <-time.After(delay):
			if s.closed.Load() {
				return
			}

			output, err := s.describer.Describe(
				s.namespace,
				s.name,
				describe.DescriberSettings{ShowEvents: true},
			)

			if err != nil {
				// Exponential backoff on error
				backoff = min(backoff*2, maxRetryInterval)
				delay = backoff
				continue
			}

			// Reset backoff on success
			backoff = defaultRefreshRate
			delay = defaultRefreshRate

			// Check if content changed
			newHash := hashString(output)
			s.hashMu.Lock()
			changed := newHash != s.lastHash
			if changed {
				s.lastHash = newHash
			}
			s.hashMu.Unlock()

			if changed {
				// Non-blocking send - drop if channel full
				select {
				case s.outputCh <- output:
				default:
				}
			}
		}
	}
}

func (s *describeSession) read() *string {
	select {
	case content := <-s.outputCh:
		return &content
	default:
		return nil
	}
}

func (s *describeSession) isOpen() bool {
	return !s.closed.Load()
}

func (s *describeSession) close() {
	if s.closed.Swap(true) {
		return // Already closed
	}
	close(s.closeCh)
	sessions.Delete(s.id)
}

func hashString(s string) string {
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:])
}

// FFI exports

//export CreateDescribeSession
func CreateDescribeSession(
	cGroup, cVersion, cResource, cNamespace, cName, cContext *C.char,
) C.ulonglong {
	group := C.GoString(cGroup)
	version := C.GoString(cVersion)
	resource := C.GoString(cResource)
	namespace := C.GoString(cNamespace)
	name := C.GoString(cName)
	context := C.GoString(cContext)

	session, errMsg := newDescribeSession(group, version, resource, namespace, name, context)
	if session == nil {
		// Return 0 to indicate error - caller should use DescribeResource for error message
		_ = errMsg
		return 0
	}

	return C.ulonglong(session.id)
}

//export DescribeSessionRead
func DescribeSessionRead(sessionID C.ulonglong) *C.char {
	v, ok := sessions.Load(uint64(sessionID))
	if !ok {
		return nil
	}

	session := v.(*describeSession)
	content := session.read()
	if content == nil {
		return nil
	}

	return C.CString(*content)
}

//export DescribeSessionIsOpen
func DescribeSessionIsOpen(sessionID C.ulonglong) C.int {
	v, ok := sessions.Load(uint64(sessionID))
	if !ok {
		return 0
	}

	session := v.(*describeSession)
	if session.isOpen() {
		return 1
	}
	return 0
}

//export DescribeSessionClose
func DescribeSessionClose(sessionID C.ulonglong) {
	v, ok := sessions.LoadAndDelete(uint64(sessionID))
	if !ok {
		return
	}

	session := v.(*describeSession)
	session.close()
}
