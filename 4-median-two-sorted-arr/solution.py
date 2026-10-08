class Solution:
    def findMedianSortedArrays(self, nums1: list[int], nums2: list[int]) -> float:
        l1 = len(nums1)
        l2 = len(nums2)
        total = l1 + l2
        even = total % 2 == 0
        mid = int((l1 + l2) // 2)

        merge = []

        i = 0
        j = 0
        for _ in range(mid + 1):
            if i < l1 and j < l2:
                if nums1[i] <= nums2[j]:
                    merge.append(nums1[i])
                    i += 1
                else:
                    merge.append(nums2[j])
                    j += 1
            elif i < l1:
                merge.append(nums1[i])
                i += 1
            elif j < l2:
                merge.append(nums2[j])
                j += 1
        #print(merge)

        if not merge:
            return 0.0
        
        end = len(merge) - 1

        if even:
            return (merge[end - 1] + merge[end]) / 2
        return merge[end]
