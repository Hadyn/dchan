pragma solidity ^0.5.1;

contract DChan {
    // Queue is a generic structure used for singly or doubly linked lists.
    // NOTE(271): Unwrapping this can decrease the gas cost in nested structures.
    struct Queue {
        // The ID of the object that is the head of the queue.
        uint32 head;

        // The ID of the object that is the tail of the queue.
        uint32 tail;
    }

    // Page is a reusable piece of application memory. When a post is submitted, its
    // content is written to a page of memory and the range of memory it occupies is
    // recorded.
    struct Page {
        // The next page that this page is linked to.
        uint32 next;

        // The words of memory that comprise this page.
        bytes32[] words;
    }

    struct Post {
        // The next post that this post is linked to.
        uint32 next;

        // The identifier of the page where the content starts.
        uint32 pageID;

        // Offset is the starting word in the page that the post occupies.
        uint32 offset;

        // The length of the post in words.
        uint32 length;
    }

    struct Thread {
        uint32 pagesHead;
        uint32 pagesTail;
        uint32 postsHead;
        uint32 postsTail;
        uint32 next;
        uint32 count;
        uint32 offset;
    }

    uint32 private constant NULL_REF = 0xffffffff;
    bytes32 private constant NULL_WORD = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    uint256 private constant FLAG_POST_AUTHOR  = 0x01;
    uint256 private constant FLAG_POST_NEXT    = 0x02;
    uint256 private constant FLAG_POST_PAGE = 0x04;
    uint256 private constant FLAG_POST_OFFSET  = 0x08;
    uint256 private constant FLAG_POST_LENGTH  = 0x10;

    uint256 private constant MASK_POST_AUTHOR  = 0xffffffffffffffffffffffffffffffffffffffff000000000000000000000000;
    uint256 private constant MASK_POST_NEXT    = 0x0000000000000000000000000000000000000000ffffffff0000000000000000;
    uint256 private constant MASK_POST_PAGE    = 0x000000000000000000000000000000000000000000000000ffffffff00000000;
    uint256 private constant MASK_POST_OFFSET  = 0x00000000000000000000000000000000000000000000000000000000ffff0000;
    uint256 private constant MASK_POST_LENGTH  = 0x000000000000000000000000000000000000000000000000000000000000ffff;

    uint256 private constant FLAG_THREAD_PAGES_HEAD = 0x01;
    uint256 private constant FLAG_THREAD_PAGES_TAIL = 0x02;
    uint256 private constant FLAG_THREAD_POSTS_HEAD = 0x04;
    uint256 private constant FLAG_THREAD_POSTS_TAIL = 0x08;
    uint256 private constant FLAG_THREAD_NEXT       = 0x10;
    uint256 private constant FLAG_THREAD_PREV       = 0x20;
    uint256 private constant FLAG_THREAD_COUNT      = 0x40;
    uint256 private constant FLAG_THREAD_OFFSET     = 0x80;

    // The maximum number of words that the content of a post can be.
    uint256 public maximumContentLength;

    // The current maximum number of pages that can exist in the contract.
    uint256 public maximumPages;

    // The current maximum number of posts that can exist.
    uint256 public maximumPosts;

    // The current maximum number of threads that can exist.
    uint256 public maximumThreads;

    // Indicates if the contract has been initialized and is live.
    bool private initialized;

    // All of the pages of memory that are contained within the contract mapped by their id.
    mapping(uint256 => Page) pages;

    // The current number of memory pages in the contract.
    uint256 pageCount;

    // A queue of all the pages that are currently not being used by threads.
    Queue unallocatedPages;

    // All of the posts that are contained within the contract mapped by their id.
    mapping(uint256 => Post) posts;

    // The current number of posts in the contract.
    uint256 postCount;

    // All the posts that are currently not being used by threads.
    Queue unallocatedPosts;

    // All of the threads that are contained within the contract mapped by their id.
    mapping(uint256 => Thread) threads;

    // The current number of threads in the contract.
    uint256 threadCount;

    // All the threads that are currently being used with the least recent updated thread
    // at the top of the queue.
    Queue allocatedThreads;

    // All the threads that are currently not being used.
    Queue unallocatedThreads;

    // Initializes the contract and marks that it is ready to be used.
    function init(
        uint256 _maximumContentLength,
        uint256 _maximumPages,
        uint256 _maximumPosts,
        uint256 _maximumThreads
    ) public {
        maximumContentLength = _maximumContentLength;
        maximumPages = _maximumPages;
        maximumPosts = _maximumPosts;
        maximumThreads = _maximumThreads;

        unallocatedPages.head = NULL_REF;
        unallocatedPages.tail = NULL_REF;

        unallocatedPosts.head = NULL_REF;
        unallocatedPosts.tail = NULL_REF;

        allocatedThreads.head = NULL_REF;
        allocatedThreads.tail = NULL_REF;

        unallocatedThreads.head = NULL_REF;
        unallocatedThreads.tail = NULL_REF;

        initialized = true;
    }

    // IsInitialized is a modifier which is prepended to functions to immediately
    // revert if the contract has not yet been initialized.
    modifier isInitialized() {
        require(initialized, "Contract has not yet been initialized.");
        _;
    }

    // GetMaximumContentLengthBytes returns the maximum number of bytes that the
    // content of a post can be.
    function getMaximumContentLengthBytes() public view returns (uint256) {
        return maximumContentLength << 5;
        // 256 bits/32 bytes per word
    }

    // InitializeMemory initializes pages of memory and returns the number of
    // pages that were successfully initialized. The number of pages that can
    // be initialized is dependant on the current number of initialized pages
    // and the current maximum number of pages allowed to be initialized. If
    // no pages were successfully initialized, this function reverts.
    function initializeMemory(uint256 n) isInitialized public returns (uint256 count) {
        require(pageCount < maximumPages, "pages already allocated");

        // Limit the number of pages to being at most the number of pages needed
        // to reach the maximum number of pages.
        uint256 remaining = maximumPages - pageCount;
        if (n > remaining) {
            n = remaining;
        }

        // Copy the current number of initialized pages into local
        // memory. This is so that we can update it as we execute
        // the function and then write the value at the end.
        uint256 counter = pageCount;

        for (uint256 i = 0; i < n; i++) {
            // Page identifiers start at zero so offset from the counter
            // by one. This is to assure that all values associated
            // with pages are non-zero and after initialization always
            // incur being updated (5000 gas) rather than being deleted
            // and reinitialized.
            uint256 id = counter + 1;

            // Initialize the page in memory and then copy it into storage.
            Page memory page = Page({
                next : NULL_REF,
                words : new bytes32[](maximumContentLength)
                });

            for (uint256 j = 0; j < maximumContentLength; j++) {
                page.words[j] = NULL_WORD;
            }

            pages[id] = page;

            // If the free page list is not empty, append the page as the tail.
            // Otherwise, initialize the list.
            if (unallocatedPages.tail != NULL_REF) {
                Page storage tail = pages[unallocatedPages.tail];
                tail.next = uint32(id);

                unallocatedPages.tail = uint32(id);
            } else {
                unallocatedPages.head = uint32(id);
                unallocatedPages.tail = uint32(id);
            }

            counter++;
        }

        pageCount = counter;

        return n;
    }

    // InitializePosts initializes post objects and returns the number of
    // posts that were successfully initialized. The number of posts that can
    // be initialized is dependant on the current number of initialized posts
    // and the current maximum number of posts allowed to be initialized. If
    // no posts can be initialized, this function reverts.
    function initializePosts(uint256 n) isInitialized public returns (uint256 count) {
        require(postCount < maximumPosts, "posts already allocated");

        uint256 remaining = maximumPosts - postCount;
        if (n > remaining) {
            n = remaining;
        }

        uint256 counter = postCount;

        for (uint256 i = 0; i < n; i++) {
            uint256 id = counter + 1;

            Post memory post = Post({
                next : NULL_REF,
                pageID : NULL_REF,
                offset : NULL_REF,
                length : NULL_REF
                });

            posts[id] = post;

            if (unallocatedPosts.tail != NULL_REF) {
                Post storage tail = posts[unallocatedPosts.tail];
                tail.next = uint32(id);

                unallocatedPosts.tail = uint32(id);
            } else {
                unallocatedPosts.head = uint32(id);
                unallocatedPosts.tail = uint32(id);
            }

            counter++;
        }

        postCount = counter;

        return n;
    }

    // InitializeThreads initializes thread objects and returns the number of
    // posts that were successfully initialized. The number of threads that can
    // be initialized is dependant on the current number of initialized threads
    // and the current maximum number of threads allowed to be initialized. If
    // no threads can be initialized, this function reverts.
    function initializeThreads(uint256 n) isInitialized public returns (uint256 count) {
        require(n > 0, "number of threads must be greater than zero");
        require(threadCount < maximumThreads, "threads already allocated");

        uint256 remaining = maximumThreads - threadCount;
        if (n > remaining) {
            n = remaining;
        }

        uint256 counter = threadCount;

        for (uint256 i = 0; i < n; i++) {
            uint256 id = counter + 1;

            // Offset can be set to zero since the structure takes up a single word and is non-zero.
            // If the gas starts acting up because the length of the fields were changed, the
            // offset being zero is probably why.
            Thread memory thread = Thread({
                pagesHead : NULL_REF,
                pagesTail : NULL_REF,
                postsHead : NULL_REF,
                postsTail : NULL_REF,
                next : NULL_REF,
                count : NULL_REF,
                offset : 0
                });

            threads[id] = thread;

            if (unallocatedThreads.tail != NULL_REF) {
                Thread storage tail = threads[unallocatedThreads.tail];
                tail.next = uint32(id);

                unallocatedThreads.tail = uint32(id);
            } else {
                unallocatedThreads.head = uint32(id);
                unallocatedThreads.tail = uint32(id);
            }

            counter++;
        }

        threadCount = counter;

        return n;
    }

    function publish(uint256 threadID, bytes32[] memory content) public returns (uint256 threadID) {
        require(content.length > 0, "content is too short");
        require(content.length <= maximumContentLength, "content is too long");

        // Check if we're creating a new thread, if we are then attempt to allocate a
        // thread. Otherwise, check that the thread exists in the contract.
        bool createThread = threadID == 0x0;
        if (createThread) {
            threadID = allocateThread();
            require(threadID != NULL_REF, "failed to allocate thread");
        } else {
            require(threadID < threadCount, "thread does not exist");
        }

        Thread storage thread = threads[threadID];

        uint256 postID = allocatePost();
        require(postID != NULL_REF, "failed to allocate post");

        Post storage post = posts[postID];

        if (createThread) {
            uint256 pageID = allocatePage();
            require(pageID != NULL_REF, "failed to allocate memory");

            post.pageID = uint32(pageID);
            post.offset = 0;
            post.length = uint32(content.length);

            thread.pagesHead = uint32(pageID);
            thread.pagesTail = uint32(pageID);
            thread.postsHead = uint32(postID);
            thread.postsTail = uint32(postID);
            thread.offset = uint32(content.length);
            thread.count = 1;

            Page storage page = pages[pageID];

            for (uint256 i = 0; i < content.length; i++) {
                page.words[i] = content[i];
            }
        } else {
            Post storage postTail = posts[thread.postsTail];
            postTail.next = uint32(postID);

            uint256 pageOffset = thread.offset % maximumContentLength;

            // Compute the remaining number of words in the most recently allocated page.
            // Finish filling the page before requesting a new page be allocated.
            uint256 write = maximumContentLength - pageOffset;
            if (write > content.length) {
                write = content.length;
            }

            for (uint256 i = 0; i < write; i++) {
                pages[thread.pagesTail].words[pageOffset + i] = content[i];
            }

            // If the currently allocated page wasn't large enough to store the post
            // then allocate a new page and write the remaining data.
            if (write < content.length) {
                uint256 splashID = allocatePage();
                require(splashID != NULL_REF, "failed to allocate memory");

                for (uint256 i = 0; i < content.length - write; i++) {
                    pages[splashID].words[i] = content[write + i];
                }

                uint256 firstPageID = splashID;
                if (write > 0) {
                    firstPageID = thread.pagesTail;
                }

                post.pageID = uint32(firstPageID);
                post.offset = uint32(pageOffset);
                post.length = uint32(content.length);

                Page storage pageTail = pages[thread.pagesTail];
                pageTail.next = uint32(splashID);

                thread.pagesTail = uint32(splashID);
                thread.postsTail = uint32(postID);
                thread.offset = uint32(thread.offset + content.length);
                thread.count = uint32(thread.count + 1);
            } else {
                post.pageID = uint32(thread.postsTail);
                post.offset = uint32(pageOffset);
                post.length = uint32(content.length);

                thread.postsTail = uint32(postID);
                thread.offset = uint32(thread.offset + content.length);
                thread.count = uint32(thread.count + 1);
            }
        }

        return threadID;
    }

    // AllocateMemory allocates or reserves a single page of memory and returns
    // its identifier. If a page could not be allocated then this function
    // returns NULL_REF.
    //
    // TODO(271): There has to be a way to bundle all the allocate functions.
    function allocatePage() isInitialized private returns (uint256 id) {
        uint256 id = unallocatedPages.head;

        if (id == NULL_REF) {
            return NULL_REF;
        }

        if (id == unallocatedPages.tail) {
            unallocatedPages.head = NULL_REF;
            unallocatedPages.tail = NULL_REF;
        } else {
            unallocatedPages.head = pages[id].next;
        }

        return id;
    }

    function allocatePost() isInitialized private returns (uint256 id) {
        uint256 id = unallocatedPosts.head;

        if (id == NULL_REF) {
            return NULL_REF;
        }

        if (id == unallocatedPosts.tail) {
            unallocatedPosts.head = NULL_REF;
            unallocatedPosts.tail = NULL_REF;
        } else {
            unallocatedPosts.head = posts[id].next;
        }

        return id;
    }

    function allocateThread() isInitialized private returns (uint256 id) {
        uint256 id = unallocatedThreads.head;

        if (id == NULL_REF) {
            return NULL_REF;
        }

        if (id == unallocatedThreads.tail) {
            unallocatedThreads.head = NULL_REF;
            unallocatedThreads.tail = NULL_REF;
        } else {
            unallocatedThreads.head = threads[id].next;
        }

        return id;
    }

    // [ 0-20] address: Author
    // [20-24]  uint32: Next
    // [24-28]  uint32: Page
    // [28-30]  uint16: Offset
    // [30-32]  uint16: Length
    function packPost(
        uint256 value,
        address author,
        uint256 next,
        uint256 page,
        uint256 offset,
        uint256 length,
        uint256 flags
    ) public pure returns (uint256) {
        if ((flags & FLAG_POST_AUTHOR) != 0) {
            value = (value & ~MASK_POST_AUTHOR) | (uint256(author) << 96);
        }

        if ((flags & FLAG_POST_NEXT) != 0) {
            value = (value & ~MASK_POST_NEXT)   | (next << 64);
        }

        if ((flags & FLAG_POST_PAGE) != 0) {
            value = (value & ~MASK_POST_PAGE)   | (page << 32);
        }

        if ((flags & FLAG_POST_OFFSET) != 0) {
            value = (value & ~MASK_POST_OFFSET) | (offset << 16);
        }

        if ((flags & FLAG_POST_LENGTH) != 0) {
            value = (value & ~MASK_POST_LENGTH) | length;
        }

        return value;
    }

    function packThread(
        uint256 value,
        uint256 next,
        uint256 prev,
        uint256 pagesHead,
        uint256 pagesTail,
        uint256 postsHead,
        uint256 postsTail,
        uint256 count,
        uint256 offset,
        uint256 flags
    ) public pure returns (uint256) {
        // [00-04] uint32: Next
        // [04-08] uint32: Prev
        // [08-12] uint32: PagesHead
        // [12-16] uint32: PagesTail
        // [16-20] uint32: PostsHead
        // [20-24] uint32: PostsTail
        // [24-26] uint16: Count
        // [26-28] uint16: Offset
        // [28-32]       : Reserved

        return 0;
    }
}