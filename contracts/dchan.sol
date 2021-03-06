contract DChan {
    uint256 private constant NULL_REF    = 0xffffff;
    uint256 private constant NULL_META   = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    bytes32 private constant NULL_DIGEST = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    uint256 private constant FLAG_QUEUE_HEAD  = 0x1;
    uint256 private constant FLAG_QUEUE_TAIL  = 0x2;
    uint256 private constant MASK_QUEUE_HEAD  = 0xffffff0000000000000000000000000000000000000000000000000000000000;
    uint256 private constant MASK_QUEUE_TAIL  = 0x000000ffffff0000000000000000000000000000000000000000000000000000;
    uint256 private constant SHIFT_QUEUE_HEAD = 232;
    uint256 private constant SHIFT_QUEUE_TAIL = 208;

    uint256 private constant FLAG_POST_NEXT         = 0x1;
    uint256 private constant FLAG_POST_AUTHOR       = 0x2;
    uint256 private constant FLAG_POST_DIGEST_FN    = 0x4;
    uint256 private constant FLAG_POST_DIGEST_SIZE  = 0x8;
    uint256 private constant MASK_POST_NEXT         = 0xffffff0000000000000000000000000000000000000000000000000000000000;
    uint256 private constant MASK_POST_AUTHOR       = 0x000000ffffffffffffffffffffffffffffffffffffffff000000000000000000;
    uint256 private constant MASK_POST_DIGEST_FN    = 0x0000000000000000000000000000000000000000000000ff0000000000000000;
    uint256 private constant MASK_POST_DIGEST_SIZE  = 0x000000000000000000000000000000000000000000000000ff00000000000000;
    uint256 private constant SHIFT_POST_NEXT        = 232;
    uint256 private constant SHIFT_POST_AUTHOR      = 72;
    uint256 private constant SHIFT_POST_DIGEST_FN   = 64;
    uint256 private constant SHIFT_POST_DIGEST_SIZE = 56;

    uint256 private constant FLAG_THREAD_NEXT       = 0x1;
    uint256 private constant FLAG_THREAD_POST_HEAD  = 0x2;
    uint256 private constant FLAG_THREAD_POST_TAIL  = 0x4;
    uint256 private constant FLAG_THREAD_COUNT      = 0x8;
    uint256 private constant MASK_THREAD_NEXT       = 0xffffff0000000000000000000000000000000000000000000000000000000000;
    uint256 private constant MASK_THREAD_POST_HEAD  = 0x000000ffffff0000000000000000000000000000000000000000000000000000;
    uint256 private constant MASK_THREAD_POST_TAIL  = 0x000000000000ffffff0000000000000000000000000000000000000000000000;
    uint256 private constant MASK_THREAD_COUNT      = 0x000000000000000000ffff000000000000000000000000000000000000000000;
    uint256 private constant SHIFT_THREAD_NEXT      = 232;
    uint256 private constant SHIFT_THREAD_PREV      = 208;
    uint256 private constant SHIFT_THREAD_POST_HEAD = 184;
    uint256 private constant SHIFT_THREAD_POST_TAIL = 160;

    struct Thread {
        uint256 meta;
    }

    struct Post {
        bytes32 digest;
        uint256 meta;
    }

    mapping(uint256 => Thread) private threads;
    uint256 private threadCounter = 1;

    uint256 private unallocatedThreads;
    uint256 private allocatedThreads;

    mapping(uint256 => Post) private posts;
    uint256 private postCounter = 1;

    uint256 private unallocatedPosts;

    constructor() public {
        unallocatedThreads = encodeQueue(0, NULL_REF, NULL_REF, FLAG_QUEUE_HEAD | FLAG_QUEUE_TAIL);
        allocatedThreads   = encodeQueue(0, NULL_REF, NULL_REF, FLAG_QUEUE_HEAD | FLAG_QUEUE_TAIL);
        unallocatedPosts   = encodeQueue(0, NULL_REF, NULL_REF, FLAG_QUEUE_HEAD | FLAG_QUEUE_TAIL);
    }

    function initializeThreads(uint256 n)
        public
    {
        (uint256 head, uint256 tail) = decodeQueue(unallocatedThreads);

        uint256 counter = threadCounter;
        for (uint256 i = 0; i < n; i++) {
            threads[counter] = Thread({
                meta: NULL_META
            });

            if (head == NULL_REF) {
                head = counter;
            }
            tail = counter;

            counter++;
        }

        unallocatedThreads = encodeQueue(0, head, tail, FLAG_QUEUE_HEAD | FLAG_QUEUE_TAIL);
        threadCounter = counter;
    }

    function initializePosts(uint256 n)
        public
    {
        (uint256 head, uint256 tail) = decodeQueue(unallocatedPosts);

        uint256 counter = postCounter;
        for (uint256 i = 0; i < n; i++) {
            posts[counter] = Post({
                digest: NULL_DIGEST,
                meta:   NULL_META
            });

            if (head == NULL_REF) {
                head = counter;
            }
            tail = counter;

            counter++;
        }

        unallocatedPosts = encodeQueue(0, head, tail, FLAG_QUEUE_HEAD | FLAG_QUEUE_TAIL);
        postCounter = counter;
    }

    function post(
        uint256 threadID,
        uint256 digestFn,
        uint256 digestSize,
        bytes32 digest
    )
        public
    {
        uint256 scratch;
        if (threadID == 0) {
            threadID = allocateThread();
            scratch |= 0x1;
        }

        uint256 postID = allocatePost();

        if ((scratch & 0x1) != 0) {
            (uint256 head, uint256 tail) = decodeQueue(allocatedThreads);

            threads[threadID] = Thread({
                meta: encodeThreadMetadata(
                    0,
                    NULL_REF,
                    postID,
                    postID,
                    1,
                    FLAG_THREAD_NEXT      |
                    FLAG_THREAD_POST_HEAD |
                    FLAG_THREAD_POST_TAIL |
                    FLAG_THREAD_COUNT
                )
            });

            posts[postID] = Post({
                digest: digest,
                meta:   encodePostMetadata(
                    0,
                    NULL_REF,
                    msg.sender,
                    digestFn,
                    digestSize,
                    FLAG_POST_NEXT        |
                    FLAG_POST_AUTHOR      |
                    FLAG_POST_DIGEST_FN   |
                    FLAG_POST_DIGEST_SIZE
                )
            });

            if (head == NULL_REF) {
                allocatedThreads = encodeQueue(0, threadID, threadID, FLAG_QUEUE_HEAD | FLAG_QUEUE_TAIL);
            } else {
                allocatedThreads = encodeQueue(
                    0,
                    head,
                    threadID,
                    FLAG_QUEUE_HEAD | FLAG_QUEUE_TAIL
                );

                thread[tail] = Thread({
                    meta: encodeThreadMetadata(
                        threads[tail].meta,
                        threadID,
                        0,
                        0,
                        0,
                        FLAG_THREAD_NEXT
                    )
                });
            }
        } else {
            uint256 threadMeta = threads[threadID].meta;

            threads[threadID] = Thread({
                meta: encodeThreadMetadata(
                    threadMeta,
                    0,
                    0,
                    postID,
                    decodeThreadCount(threadMeta) + 1,
                    FLAG_THREAD_POST_TAIL |
                    FLAG_THREAD_COUNT
                )
            });

            posts[postID] = Post({
                digest: digest,
                meta:   encodePostMetadata(
                    0,
                    NULL_REF,
                    msg.sender,
                    digestFn,
                    digestSize,
                    FLAG_POST_NEXT        |
                    FLAG_POST_AUTHOR      |
                    FLAG_POST_DIGEST_FN   |
                    FLAG_POST_DIGEST_SIZE
                )
            });

            uint256 tail = decodeThreadPostTail(threadMeta);

            posts[tail].meta = encodePostMetadata(
                posts[tail].meta,
                postID,
                0,
                0,
                0,
                FLAG_POST_NEXT
            );
        }
    }

    function decodeQueue(uint256 value)
        public
        pure
        returns (uint256 head, uint256 tail)
    {
        return (
            (value & MASK_QUEUE_HEAD) >> SHIFT_QUEUE_HEAD,
            (value & MASK_QUEUE_TAIL) >> SHIFT_QUEUE_TAIL
        );
    }

    function decodeQueueHead(
        uint256 value
    )
        public
        pure
        returns (uint256)
    {
        return (value & MASK_QUEUE_HEAD) >> SHIFT_QUEUE_HEAD;
    }

    function decodeQueueTail(
        uint256 value
    )
        public
        pure
        returns (uint256)
    {
        return (value & MASK_QUEUE_TAIL) >> SHIFT_QUEUE_TAIL;
    }

    function encodeQueue(
        uint256 value,
        uint256 head,
        uint256 tail,
        uint256 flags
    )
        public
        pure
        returns (uint256)
    {
        if ((flags & FLAG_QUEUE_HEAD) != 0) {
            value = (value & ~MASK_QUEUE_HEAD) | (head << SHIFT_QUEUE_HEAD);
        }

        if ((flags & FLAG_QUEUE_TAIL) != 0) {
            value = (value & ~MASK_QUEUE_TAIL) | (tail << SHIFT_QUEUE_TAIL);
        }

        return value;
    }

    function decodeThreadNext(
        uint256 value
    )
        public
        pure
        returns (uint256)
    {
        return (value & MASK_THREAD_NEXT) >> SHIFT_THREAD_NEXT;
    }

    function decodeThreadMetadata(
        uint256 value
    )
        public
        pure
        returns (uint256 next, uint256 postHead, uint256 postTail, uint256 count)
    {
        return (
            (value & MASK_THREAD_NEXT)      >> SHIFT_THREAD_NEXT,
            (value & MASK_THREAD_POST_HEAD) >> SHIFT_THREAD_POST_HEAD,
            (value & MASK_THREAD_POST_TAIL) >> SHIFT_THREAD_POST_TAIL,
            (value & MASK_THREAD_COUNT)     >> SHIFT_THREAD_COUNT
        );
    }

    function encodeThreadMetadata(
        uint256 value,
        uint256 next,
        uint256 postHead,
        uint256 postTail,
        uint256 count,
        uint256 flags
    )
        public
        pure
        returns (uint256 meta)
    {
        if ((flags & FLAG_THREAD_NEXT) != 0) {
            value = (value & ~MASK_THREAD_NEXT) | (head << SHIFT_THREAD_NEXT);
        }

        if ((flags & FLAG_THREAD_POST_HEAD) != 0) {
            value = (value & ~MASK_THREAD_POST_HEAD) | (tail << SHIFT_THREAD_POST_HEAD);
        }

        if ((flags & FLAG_THREAD_POST_TAIL) != 0) {
            value = (value & ~MASK_THREAD_POST_TAIL) | (tail << SHIFT_THREAD_POST_TAIL);
        }

        if ((flags & FLAG_THREAD_COUNT) != 0) {
            value = (value & ~MASK_THREAD_COUNT) | (tail << SHIFT_THREAD_COUNT);
        }

        return value;
    }

    function decodePostMetadata(uint256 value)
        public
        pure
        returns (uint256 next, address author, uint256 digestFn, uint256 digestSize)
    {
        return (
            (value & MASK_THREAD_NEXT)         >> SHIFT_THREAD_NEXT,
            address((value & MASK_POST_AUTHOR) >> SHIFT_POST_AUTHOR),
            (value & MASK_POST_DIGEST_FN)      >> SHIFT_POST_DIGEST_FN,
            (value & MASK_POST_DIGEST_SIZE)    >> SHIFT_POST_DIGEST_SIZE
        );
    }

    function decodePostNext(
        uint256 value
    )
        public
        pure
        returns (uint256)
    {
        return (value & MASK_POST_NEXT) >> SHIFT_POST_NEXT;
    }

    function encodePostMetadata(
        uint256 value,
        uint256 next,
        address author,
        uint256 digestFn,
        uint256 digestSize,
        uint256 flags
    )
        public
        pure
        returns (uint256 meta)
    {
        return 0;
    }

    function allocateThread()
        private
        returns (uint256 id)
    {
        (uint256 head, uint256 tail) = decodeQueue(unallocatedThreads);

        if (head == NULL_REF) {
            free();

            // TODO
        }

        if (head == tail) {
            unallocatedThreads = encodeQueue(0, NULL_REF, NULL_REF, FLAG_QUEUE_HEAD | FLAG_QUEUE_TAIL);
        } else {
            unallocatedThreads = encodeQueue(
                0,
                decodeThreadNext(threads[head].meta),
                tail,
                FLAG_QUEUE_HEAD | FLAG_QUEUE_TAIL
            );
        }

        return head;
    }

    function allocatePost()
        private
        returns (uint256 id)
    {
        (uint256 head, uint256 tail) = decodeQueue(unallocatedPosts);

        if (head == NULL_REF) {
            free();

            // TODO
        }

        if (head == tail) {
            unallocatedPosts = encodeQueue(0, NULL_REF, NULL_REF, FLAG_QUEUE_HEAD | FLAG_QUEUE_TAIL);
        } else {
            unallocatedPosts = encodeQueue(
                0,
                decodePostNext(posts[head].meta),
                tail,
                FLAG_QUEUE_HEAD | FLAG_QUEUE_TAIL
            );
        }

        return head;
    }

    function free()
        private
    {
    }
}