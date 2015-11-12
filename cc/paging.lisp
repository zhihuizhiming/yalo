;;;; -*- Mode: Lisp -*-
;;;; Author:
;;;;     Yujian Zhang <yujian.zhang@gmail.com>
;;;; Description:
;;;;     Paging functions.
;;;; References:
;;;;     [1] AMD64 Architecture Programmer's Manual Volume 2: System Programming.
;;;;         Publication No. 24593; Revision: 3.25
;;;; License:
;;;;     GNU General Public License v2
;;;;     http://www.gnu.org/licenses/gpl-2.0.html
;;;; Copyright (C) 2015 Yujian Zhang

(in-package :cc)

(defparameter *paging-32*
  `(
    ;;; Technical details for 2 MB page translation can be found in
    ;;; section 5.3.4 (2-Mbyte Page Translation) of [1].
    ;;; At the beginning, paging setup is based on
    ;;; http://wiki.osdev.rg/Entering_Long_Mode_Directly
    ;;;
    ;;; Setup two mappings:
    ;;;   1) Identity mapping for bottom 2 MB physical address.
    ;;;   2) Map ALL available physical memory to higher memory space
    ;;;      starting from -2GB memory space: #xffffffff80000000
    ;;; Identity mapping will be removed after entering 64 bit mode
    ;;; by calling function unmap-lower-memory.
    ;;;
    ;;; Suppose PML4 points to address A (`pml4-base` below), then there are
    ;;; 5 4 KB memory regions to be processed by this function:
    ;;;   A          .. A + #x0fff: Page Map Level 4
    ;;;   A + #x1000 .. A + #x1fff: Page Directory Pointer Table for identity mapping.
    ;;;   A + #x2000 .. A + #x2fff: Page Directory Table for identity mapping.
    ;;;   A + #x3000 .. A + #x3fff: Page Directory Pointer Table for higher half mapping.
    ;;;   A + #x4000 .. A + #x4fff: Page Directory Table for higher half mapping.

    setup-paging

    (equ     pml4-base #x9000)
    (equ     page-present-writable (+ 2 1))   ; Flags indicate the page is present and writable.
    (equ     page-present-writable-pde.ps (+ 128 2 1)) ; In addition to above flags, set PDE.PS for 2 MB page.

    (equ     kernel-virtual-base #xffffffff80000000) ; Start virtual address for higher half kernel.

    (push    edx)
    (push    ecx)
    (push    ebx)
    (push    edi)

    (call32  get-memory-size)
    ;; TODO. So far we only handle < 4GB memory. As memory size is in
    ;; EDX:EAX, we ignore the value in EDX for now.
    (mov     edx eax)

    ;; Zero out the 5 * 4 kB buffer.
    (mov     edi pml4-base)
    (mov     ecx #x1400)
    (xor     eax eax)
    (cld)
    (rep     stosd)
    (mov     edi pml4-base)

    ;; Build the Page Map Level 4.
    ;; First set entry the identity mapping.
    (mov     eax edi)
    (add     eax #x1000)              ; Address of the Page Directory Pointer Table for identity mapping.
    (or      eax page-present-writable)
    (mov     (edi) eax)
    ;; Secondly set entry for higher half mapping.
    (add     eax #x2000)              ; Address of the Page Directory Pointer Table for higher half mapping.
    (mov     ebx 511)                 ; The last entry in the 512 entry table.
    (mov     (ebx*8 edi) eax)

    ;; Build the Page Directory Pointer Table for identity mapping.
    (mov     eax edi)
    (add     eax #x2000)              ; Address of the Page Directory.
    (or      eax page-present-writable)
    (mov     (edi #x1000) eax)

    ;; Build the Page Directory Table for identity mapping. Just map 2 MB.
    (mov     eax page-present-writable-pde.ps) ; Effectively point EAX to address #x0.
    (mov     (edi #x2000) eax)

    ;; Build the Page Directory Pointer Table for higher half mapping.
    (mov     edi (+ pml4-base #x3000))
    (mov     eax edi)
    (add     eax #x1000)              ; Address of the Page Directory.
    (or      eax page-present-writable)
    ;; TODO: we only map maximum 1 GB memory now. So we only handle the 2nd last entry here.
    (mov     ebx 510)                 ; The second last entry in the 512 entry table.
    (mov     (ebx*8 edi) eax)

    ;; Build the Page Directory Table for higher half mapping.
    (add     edi #x1000)
    (mov     eax page-present-writable-pde.ps) ; Effectively point EAX to address #x0.
    .loop-page-directory-table
    (mov     (edi) eax)
    (add     eax #x200000)            ; Increase 2 MB.
    (add     edi 8)
    (cmp     eax edx)                 ; Has all memory been mapped?
    (jb      .loop-page-directory-table)

    (pop     edi)
    (pop     ebx)
    (pop     ecx)
    (pop     edx)

    (ret)))

(defparameter *paging-64*
  `(
    ;;; Remove identity mapping of bottom 2 MB.
    ,@(def-fun 'unmap-lower-memory nil `(
    (mov     rdi pml4-base)
    (mov     qword (rdi) 0)
    (invlpg  (abs 0))
    ))))
