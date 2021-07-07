#!/usr/bin/env python3

import os
import ast
import pdb
import sys
import errno
import shutil
import argparse

def get_mozbuild_files(moz_central):
	for (dirpath, dirnames, filenames) in os.walk(moz_central):
		for f in filenames:
			if f == "moz.build":
				fullpath = os.path.join(dirpath, f)
				if "/win/" in fullpath:
					continue
				elif "/windows/" in fullpath:
					continue
				elif "/android/" in fullpath:
					continue
				elif "/mac/" in fullpath:
					continue
				elif "/test/" in fullpath:
					continue
				elif "/accessible/other/" in fullpath:
					continue
				yield fullpath
	

def get_ast(path):
    source = open(path).read()
    root = ast.parse(source)
    # Populate node parents. This allows us to walk up from a node to the root.
    # (Really I think python's ast class should do this, but it doesn't, so we monkey-patch it)
    for node in ast.walk(root):
        for child in ast.iter_child_nodes(node):
            child.parent = node
    return (source, root)
	
def get_exports(source, root):
	all_exports = [node
		for node in ast.walk(root)
		if isinstance(node, ast.AugAssign)
		and (
			(isinstance(node.target, ast.Name) and node.target.id == "EXPORTS")
			or
			(isinstance(node.target, ast.Attribute) and "EXPORTS" in ast.get_source_segment(source, node))
			)
		]
	all_exports.extend([node
		for node in ast.walk(root)
		if isinstance(node, ast.Assign)
		and (
			(isinstance(node.targets[0], ast.Name) and node.targets[0].id in ["EXPORTS", "h_and_cpp"])
			or
			(isinstance(node.targets[0], ast.Attribute) and "EXPORTS" in ast.get_source_segment(source, node))
			)
		])
	all_exports.extend([node
		for node in ast.walk(root)
		if isinstance(node, ast.Assign)
		and (
			(isinstance(node.targets[0], ast.Subscript) and isinstance(node.targets[0].value, ast.Name) and node.targets[0].value.id == "EXPORTS")
			and
			(node.targets[0].slice.value.value == "double-conversion") # Limit it to just this one case to be safe
			)
		])
	linux_exports = []

	# For each export, see if it is contained within an if statement
	# whose conditional includes OS_ARCH or OS_TARGET and if so, only include it if it's Linux
	for e in all_exports:
		e_source = ast.get_source_segment(source, e)

		#if "XXXXXXX" in e_source:
		#	pdb.set_trace()
	
		if e.parent == root:
			linux_exports.append((e, e_source))
			continue
			
		node = e
		should_include = True
		while node.parent != root:
			code = ast.get_source_segment(source, node.parent)
			# This test will fail for a conditional like "OS_ARCH != Linux"
			#    but presently we don't have any of those...
			if isinstance(node.parent, ast.If):
				conditional = ast.get_source_segment(source, node.parent.test)
			
				# We want to ensure that the node is excluded if it is directly underneath a conditional
				# that looks like it is for another platform
				if ("OS_ARCH" in conditional or "OS_TARGET" in conditional) and "Linux" not in conditional:
					if e in node.parent.body:
						should_include = False
				if "MOZ_WIDGET_TOOLKIT" in conditional and "gtk" not in conditional:
					if e in node.parent.body:
						should_include = False
				if "MOZ_BUILD_APP" in conditional and '== "memory"' in conditional:
					if e in node.parent.body:
						should_include = False
				
			node = node.parent
				
		if should_include:
			linux_exports.append((e, e_source))
	
	return linux_exports

def get_symlink_mapping(mozilla_root, all_exports):
	# key: relative path, e.g. 'mozilla', 'mozilla/foo/'
	# value: fullpath to .h file from mozilla-central root
	to_symlink = {}

	for filename, exports in all_exports:
		for decl, source in exports:

			export_list = None
			if isinstance(decl.value, ast.ListComp):
				# e.g. EXPORTS += ["!%s.h" % stem for stem in generated]
				if '"!' in source:
					# If it has what looks like an objdir path, ignore it
					continue
				elif source == "EXPORTS.mozilla.webgpu += [x + \".h\" for x in h_and_cpp]":
					continue

				assert False, "We shouldn't wind up here because we think we've handled all these cases"
				continue
			elif isinstance(decl.value, ast.Subscript):
				# e.g. EXPORTS.vpx += files['X64_EXPORTS']
				# We're not going to attempt to figure these out.
				assert "vpx" in source or "aom" in source, "We shouldn't wind up here."
				continue
			elif isinstance(decl.value, ast.Call):
				# e.g. EXPORTS.mozilla += sorted(["!" + g for g in gen_h])
				if '"!' in source:
					# If it has what looks like an objdir path, ignore it
					continue

				assert False, "We shouldn't wind up here because we think we've handled all these cases"
				continue
			elif isinstance(decl.value, ast.Name):
				# e.g. EXPORTS.gtest += gtest_exports
				# We're not going to attempt to figure these out.
				assert "gtest" in source or "gmock" in source, "We shouldn't wind up here"
				continue
			elif isinstance(decl.value, ast.List):
				export_list = decl.value
			else:
				assert False, "We shouldn't be here."
				continue

			rel_path = ""
			special_case = False
			target = decl.target if isinstance(decl, ast.AugAssign) else decl.targets[0]
			if isinstance(target, ast.Name):
				assert target.id in ["EXPORTS", "h_and_cpp"]
				if target.id == "h_and_cpp":
					special_case = True
					rel_path = os.path.join("mozilla", "webgpu")
				else:
					rel_path = ""
			elif isinstance(target, ast.Attribute):
				toptarget = target
				subtarget = target
				rel_path = ""
				while isinstance(subtarget, ast.Attribute):
					rel_path = os.path.join(subtarget.attr, rel_path) if rel_path else subtarget.attr
					subtarget = subtarget.value
				assert isinstance(subtarget, ast.Name)
				assert subtarget.id == "EXPORTS"
			elif isinstance(target, ast.Subscript):
				assert target.value.id == "EXPORTS"
				rel_path = target.slice.value.value
			else:
				assert False
				pdb.set_trace()

			for li in export_list.elts:
				if isinstance(li, ast.BinOp):
					# e.g. EXPORTS += [osdir + "/nsOSHelperAppService.h"]
					# Not going to handle these.
					continue
				elif not isinstance(li, ast.Constant):
					assert False
					pdb.set_trace()

				list_value = li.value
				list_value_path = os.path.dirname(filename)

				if special_case:
					list_value = list_value + ".h"
				elif list_value[0] == '!':
					# We'll get these later from objdir/dist/includes
					continue
				elif list_value[0] == '/':
					list_value = list_value[1:]
					list_value_path = args.i

				if rel_path not in to_symlink:
					to_symlink[rel_path] = []

				fullpath = os.path.join(list_value_path, list_value)
				to_symlink[rel_path].append(fullpath)
		
	return to_symlink

def makedirs(path):
	try:
		os.makedirs(path)
	except OSError as exc:
	    if exc.errno != errno.EEXIST:
	        raise
	    pass

if __name__ == "__main__":
	parser = argparse.ArgumentParser()
	parser.add_argument("-i", action="store", required=True, help="input mozilla-central directory")
	parser.add_argument("-o", action="store", required=True, help="destination directory for the symlinks")
	parser.add_argument("-v", action="store_true", required=False, help="verbose output")
	args = parser.parse_args()

	for dirpath, dirnames, filenames in os.walk(args.o):
		if len(dirnames) != 0 or len(filenames) != 0:
			print("Output directory is not empty.")
			sys.exit(1)
	makedirs(args.o)

	if args.i[0] != "/" or args.o[0] != "/":
		print("Only fully-qualified paths are allowed.")
		sys.exit(1)
	
	all_exports = []
	for filepath in get_mozbuild_files(args.i):
		source, root = get_ast(filepath)
		more = get_exports(source, root)
		if len(more):
			all_exports.append((filepath, more))
			
	to_symlink = get_symlink_mapping(args.i, all_exports)
	
	for relpath, files in to_symlink.items():
		if relpath:
			makedirs(os.path.join(args.o, relpath))
		if args.v:
			print(relpath)
		for f in files:
			src = f
			dst = os.path.join(args.o, relpath, os.path.basename(f))
			if args.v:
				print("\t", f)
			try:
				os.symlink(src, dst)
			except Exception as e:
				print("Could not symlink %s to %s." % (src, dst), file=sys.stderr)
				print(e)
	
	# Now grab everything from objdir/dist/includes
	if args.v:
		print("Generated Headers")
	for (dirpath, dirnames, filenames) in os.walk(os.path.join(args.i, "objdir/dist/include/")):
		for f in filenames:
			src = os.path.join(dirpath, f)
			if args.v:
				print("\t", src)

			rel_path = dirpath.replace(args.i, "").replace("objdir/dist/include/", "").lstrip("/")
			if rel_path:
				makedirs(os.path.join(args.o, rel_path))
			dst = os.path.join(args.o, rel_path, f)
			os.symlink(src, dst)

	# Now grab everything from objdir/ipc/ipdl/_ipdlheaders
	if args.v:
		print("IPC Headers")
	for (dirpath, dirnames, filenames) in os.walk(os.path.join(args.i, "objdir/ipc/ipdl/_ipdlheaders/")):
		for f in filenames:
			src = os.path.join(dirpath, f)
			if args.v:
				print("\t", src)

			rel_path = dirpath.replace(args.i, "").replace("objdir/ipc/ipdl/_ipdlheaders/", "").lstrip("/")
			if rel_path:
				makedirs(os.path.join(args.o, rel_path))
			dst = os.path.join(args.o, rel_path, f)
			os.symlink(src, dst)

	for (dirpath, dirnames, filenames) in os.walk(os.path.join(args.i, "ipc/chromium/src/")):
		for f in filenames:
			if not f.endswith(".h"):
				continue

			src = os.path.join(dirpath, f)
			if args.v:
				print("\t", src)

			rel_path = dirpath.replace(args.i, "").replace("ipc/chromium/src/", "").lstrip("/")
			if rel_path:
				makedirs(os.path.join(args.o, rel_path))
			dst = os.path.join(args.o, rel_path, f)
			os.symlink(src, dst)

	# Now do the special icky NSPR stuff
	if args.v:
		print("NSPR Headers")
	shutil.rmtree(os.path.join(args.o, "nspr"))
	os.mkdir(os.path.join(args.o, "nspr"))

	nspr_include_dir = os.path.join(args.i, "nsprpub/pr/include")
	for (dirpath, dirnames, filenames) in os.walk(nspr_include_dir):
		for f in filenames:
			if f.endswith(".h") or f.endswith(".cfg"):
				src = os.path.join(dirpath, f)

				relative_subpath = dirpath.replace(nspr_include_dir, "")
				if relative_subpath and relative_subpath[0] == "/":
					relative_subpath = relative_subpath[1:]

				dst_dir = os.path.join(args.o, "nspr", relative_subpath)
				if not os.path.exists(dst_dir):
					os.mkdir(dst_dir)
				assert os.path.isdir(dst_dir)

				dst = os.path.join(dst_dir, f)
				if args.v:
					print("\t", src)
				os.symlink(src, dst)
	
	src = os.path.join(args.i, "config/external/nspr/prcpucfg.h")
	dst = os.path.join(args.o, "nspr/prcpucfg.h")
	os.symlink(src, dst)