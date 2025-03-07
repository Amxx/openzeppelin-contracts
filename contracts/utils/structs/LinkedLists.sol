// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Panic} from "../Panic.sol";

type Iterator is uint16;
Iterator constant BEGIN = Iterator.wrap(0);
Iterator constant END = Iterator.wrap(0);

function eq(Iterator it1, Iterator it2) pure returns (bool) {
    return Iterator.unwrap(it1) == Iterator.unwrap(it2);
}

function neq(Iterator it1, Iterator it2) pure returns (bool) {
    return Iterator.unwrap(it1) != Iterator.unwrap(it2);
}

using {eq as ==, neq as !=} for Iterator global;

library LinkedLists {
    struct Uint224Node {
        uint224 value;
        Iterator next;
        Iterator prev;
    }

    struct Uint224LinkedList {
        // element 0 contains the head/tails of the list
        mapping(Iterator => Uint224Node) _elements;
        uint16 _numAdded;
        uint16 _numRemoved;
    }

    // ============================================= Iterator operations =============================================
    function forward(Uint224LinkedList storage self, Iterator it) internal view returns (Iterator) {
        return self._elements[it].next;
    }

    function forward(Uint224LinkedList storage self, Iterator it, uint16 steps) internal view returns (Iterator) {
        for (; steps > 0; --steps) {
            it = forward(self, it);
            if (it == END) return END;
        }
        return it;
    }

    function backward(Uint224LinkedList storage self, Iterator it) internal view returns (Iterator) {
        return self._elements[it].prev;
    }

    function backward(Uint224LinkedList storage self, Iterator it, uint16 steps) internal view returns (Iterator) {
        for (; steps > 0; --steps) {
            it = backward(self, it);
            if (it == BEGIN) return BEGIN;
        }
        return it;
    }

    // ================================================ Insert / Push ================================================
    function _insert(Uint224LinkedList storage self, Iterator prev, Iterator next, uint224 value) private {
        Iterator index = Iterator.wrap(++self._numAdded);
        self._elements[index] = Uint224Node({prev: prev, next: next, value: value});
        self._elements[prev].next = index;
        self._elements[next].prev = index;
    }

    function insertAfter(Uint224LinkedList storage self, Iterator it, uint224 value) internal {
        _insert(self, it, forward(self, it), value);
    }

    function insertBefore(Uint224LinkedList storage self, Iterator it, uint224 value) internal {
        _insert(self, backward(self, it), it, value);
    }

    function insertAt(Uint224LinkedList storage self, uint16 position, uint224 value) internal {
        if (position > length(self)) Panic.panic(Panic.ARRAY_OUT_OF_BOUNDS);
        insertAfter(self, forward(self, BEGIN, position), value);
    }

    function pushFront(Uint224LinkedList storage self, uint224 value) internal {
        insertAfter(self, BEGIN, value);
    }

    function pushBack(Uint224LinkedList storage self, uint224 value) internal {
        insertBefore(self, END, value);
    }

    // ================================================ Remove / Pop =================================================
    function remove(Uint224LinkedList storage self, Iterator it) internal returns (uint224) {
        if (it == BEGIN) Panic.panic(Panic.ARRAY_OUT_OF_BOUNDS);

        uint224 value = self._elements[it].value;
        Iterator next = self._elements[it].next;
        Iterator prev = self._elements[it].prev;

        self._elements[prev].next = next;
        self._elements[next].prev = prev;
        delete self._elements[it];
        ++self._numRemoved;

        return value;
    }

    function removeAt(Uint224LinkedList storage self, uint16 position) internal returns (uint224) {
        // Panic if iterator is BEGIN/END
        return remove(self, forward(self, BEGIN, position + 1));
    }

    function popFront(Uint224LinkedList storage self) internal returns (uint224) {
        Iterator it = forward(self, BEGIN);
        if (it == END) Panic.panic(Panic.EMPTY_ARRAY_POP);
        return remove(self, it);
    }

    function popBack(Uint224LinkedList storage self) internal returns (uint224) {
        Iterator it = backward(self, END);
        if (it == END) Panic.panic(Panic.EMPTY_ARRAY_POP);
        return remove(self, it);
    }

    function clear(Uint224LinkedList storage self) internal {
        delete self._elements[BEGIN];
        delete self._numAdded;
        delete self._numRemoved;
    }

    // ================================================== Accessors ==================================================
    function at(Uint224LinkedList storage self, Iterator it) internal view returns (uint224 value) {
        return self._elements[it].value;
    }

    function front(Uint224LinkedList storage self) internal view returns (uint224 value) {
        return at(self, forward(self, BEGIN));
    }

    function back(Uint224LinkedList storage self) internal view returns (uint224 value) {
        return at(self, backward(self, END));
    }

    function length(Uint224LinkedList storage self) internal view returns (uint16) {
        return self._numAdded - self._numRemoved;
    }
}
