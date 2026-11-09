/// Disjoint sets over row IDs. Each set's representative is its smallest ID.
struct UnionFind {
    private var parent: [Int64: Int64] = [:]

    /// The representative of `id`'s set.
    mutating func find(_ id: Int64) -> Int64 {
        var root = id
        while let next = parent[root], next != root {
            root = next
        }
        // Path compression.
        var node = id
        while let next = parent[node], next != root {
            parent[node] = root
            node = next
        }
        return root
    }

    /// Merges the sets holding `a` and `b`.
    mutating func union(_ a: Int64, _ b: Int64) {
        let rootA = find(a)
        let rootB = find(b)
        guard rootA != rootB else { return }
        if rootA < rootB {
            parent[rootB] = rootA
        } else {
            parent[rootA] = rootB
        }
    }

    /// Every ID that was linked to another, mapped to its representative.
    /// IDs never passed to `union` are left out: they are their own group.
    mutating func groups() -> [Int64: Int64] {
        var result: [Int64: Int64] = [:]
        for id in Array(parent.keys) {
            result[id] = find(id)
        }
        for root in Set(result.values) {
            result[root] = root
        }
        return result
    }
}
