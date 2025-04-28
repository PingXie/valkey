start_cluster 1 0 {tags {external:skip cluster} overrides {cluster-node-timeout 1000}} {

    set primary [srv 0 "client"]

    assert_match {OK} [$primary set foo1 bar]
    assert_match {OK} [$primary set foo2 bar]
    assert_match {OK} [$primary set foo3 bar]

    test "Cross-slot multi-key get succeeds" {
        assert_match {bar bar bar} [$primary smget foo1 foo2 foo3]
    }
}

start_cluster 3 0 {tags {external:skip cluster} overrides {cluster-node-timeout 1000}} {

    set primary_0 [srv 0 "client"]
    set primary_1 [srv -1 "client"]
    set primary_2 [srv -2 "client"]

    test "Prepare keys" {
        assert_match {OK} [$primary_0 set slot4813{baz} foo]
        assert_match {OK} [$primary_0 set slot609{aga} bar]
    }

    test "Cross-slot multi-key get fails with CROSSSHARD if not all slots are owned by the same shard" {
        assert_error "CROSSSHARD*" {$primary_0 smget slot4813{baz} slot609{aga} slot12216{goodkey}}
    }

    test "Cross-slot multi-key get fails with CROSSSHARD if all slots are owned by other shards" {
        assert_error "CROSSSHARD*" {$primary_0 smget slot12216{goodkey} slot10772{goodkey2}}
    }

    test "Cross-slot multi-key get fails with MOVED if all slots are owned by a different shard" {
        assert_error "MOVED*" {$primary_0 smget slot12216{goodkey} slot14901{goodkey3}}
    }
}

start_cluster 2 0 {tags {external:skip cluster} overrides {cluster-node-timeout 1000}} {

    set primary_0 [srv 0 "client"]
    set primary_1 [srv -1 "client"]

    assert_match {OK} [$primary_0 set slot4813{baz} foo]

    test "Start migrating slot 609" {
        assert_match {OK} [$primary_0 cluster setslot 609 migrating [$primary_1 cluster myid]]
        assert_match {OK} [$primary_1 cluster setslot 609 importing [$primary_0 cluster myid]]
    }

    test "Cross-slot multi-key get succeeds on unstable slot" {
        assert_match {foo {}} [$primary_0 smget slot4813{baz} slot609{aga}]
    }

    test "Cross-slot multi-key get succeeds on stable slot" {
        assert_match {OK} [$primary_0 cluster setslot 609 stable]
        assert_match {foo {}} [$primary_0 smget slot4813{baz} slot609{aga}]
    }
}

start_cluster 1 0 {tags {external:skip cluster} overrides {cluster-node-timeout 1000 cluster-require-full-coverage no}} {

    set primary_0 [srv 0 "client"]

    assert_match {OK} [$primary_0 cluster delslots 4813]

    test "Cross-slot multi-key get failed with CLUSTERDOWN when any slot is not served" {
        assert_error "CLUSTERDOWN Hash slot not served*" {$primary_0 smget slot4813{baz} slot609{aga}}
    }

    test "Cross-slot multi-key get failed with CLUSTERDOWN when any slot is not served" {
        assert_error "CLUSTERDOWN Hash slot not served*" {$primary_0 smget slot609{aga} slot4813{baz}}
    }

    assert_match {OK} [$primary_0 cluster delslots 609]

    test "Cross-slot multi-key get failed with CLUSTERDOWN when all slots are not served" {
        assert_error "CLUSTERDOWN Hash slot not served*" {$primary_0 smget slot4813{baz} slot609{aga}}
    }
}
