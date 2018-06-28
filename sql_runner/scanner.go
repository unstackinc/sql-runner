package main

import (
	"github.com/go-pg/pg/orm"
	"github.com/go-pg/pg/types"
)

type Results []string

var _ orm.HooklessModel = (*Results)(nil)
var _ types.ValueAppender = (*Results)(nil)

func (results *Results) Init() error {
	if s := *results; len(s) > 0 {
		*results = s[:0]
	}
	return nil
}

func (results *Results) NewModel() orm.ColumnScanner {
	return results
}

func (Results) AddModel(_ orm.ColumnScanner) error {
	return nil
}

func (results *Results) ScanColumn(colIdx int, _ string, b []byte) error {
	*results = append(*results, string(b))
	return nil
}

func (results Results) AppendValue(dst []byte, quote int) []byte {
	if len(results) <= 0 {
		return dst
	}

	for _, s := range results {
		dst = types.AppendString(dst, s, 1)
		dst = append(dst, ',')
	}
	dst = dst[:len(dst)-1]
	return dst
}