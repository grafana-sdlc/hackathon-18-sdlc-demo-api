package main

import (
	"encoding/json"
	"net/http/httptest"
	"testing"
)

func TestAPI(t *testing.T) {
	for _, tc := range []struct {
		path       string
		status     int
		key, value string
	}{
		{"/healthz", 200, "status", "ok"},
		{"/api/hello", 200, "revision", revision},
		{"/unknown", 404, "", ""},
	} {
		t.Run(tc.path, func(t *testing.T) {
			w := httptest.NewRecorder()
			handler().ServeHTTP(w, httptest.NewRequest("GET", tc.path, nil))
			if w.Code != tc.status {
				t.Fatalf("status=%d want=%d", w.Code, tc.status)
			}
			if tc.key != "" {
				var body map[string]string
				if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
					t.Fatal(err)
				}
				if body[tc.key] != tc.value {
					t.Fatalf("%s=%q want=%q", tc.key, body[tc.key], tc.value)
				}
			}
		})
	}
}
