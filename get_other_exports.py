#!/usr/bin/env python3

import os
import sys
import argparse

if __name__ == "__main__":
	parser = argparse.ArgumentParser()
	parser.add_argument("-i", action="store", required=True, help="input mozilla-central directory")
	parser.add_argument("-o", action="store", required=True, help="destination directory for the symlinks")
	args = parser.parse_args()

	sys.path.append(args.i)
	from xpcom.base.ErrorList import error_list_h, error_names_internal_h

	with open(os.path.join(args.o, "ErrorList.h"), "w") as f:
		error_list_h(f)

	with open(os.path.join(args.o, "ErrorNamesInternal.h"), "w") as f:
		error_names_internal_h(f)

	xpcom_config = """
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/* Global defines needed by xpcom clients */

#ifndef _XPCOM_CONFIG_H_
#define _XPCOM_CONFIG_H_

/* Define to a string describing the XPCOM ABI in use */
#define TARGET_XPCOM_ABI "x86_64-gcc3"

#endif /* _XPCOM_CONFIG_H_ */
"""
	with open(os.path.join(args.o, "xpcom-config.h"), "w") as f:
		f.write(xpcom_config)

