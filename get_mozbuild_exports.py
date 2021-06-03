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
				elif "/mac/" in fullpath:
					continue
				elif "/test/" in fullpath:
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
			(isinstance(node.targets[0], ast.Name) and node.targets[0].id == "EXPORTS")
			or
			(isinstance(node.targets[0], ast.Attribute) and "EXPORTS" in ast.get_source_segment(source, node))
			)
		])
	linux_exports = []

	# For each export, see if it is contained within an if statement
	# whose conditional includes OS_ARCH or OS_TARGET and if so, only include it if it's Linux
	for e in all_exports:
		e_source = ast.get_source_segment(source, e)
	
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
			
				if ("OS_ARCH" in conditional or "OS_TARGET" in conditional) and "Linux" not in conditional:
					should_include = False
				if "MOZ_WIDGET_TOOLKIT" in conditional and "gtk" not in conditional:
					should_include = False
				if "MOZ_BUILD_APP" in conditional and '== "memory"' in conditional:
					should_include = False
				
			node = node.parent
				
		if should_include:
			linux_exports.append((e, e_source))
	
	return linux_exports

def get_symlink_mapping(all_exports):
	# key: relative path, e.g. 'mozilla', 'mozilla/foo/'
	# value: fullpath to .h file from mozilla-central root
	to_symlink = {}

	for filename, exports in all_exports:
		for decl, source in exports:

			export_list = None
			if isinstance(decl.value, ast.ListComp):
				# e.g. EXPORTS += ["!%s.h" % stem for stem in generated]
				# We're not going to attempt to figure these out.
				continue
			elif isinstance(decl.value, ast.Subscript):
				# e.g. EXPORTS.vpx += files['X64_EXPORTS']
				# We're not going to attempt to figure these out.
				continue
			elif isinstance(decl.value, ast.Call):
				# e.g. EXPORTS.mozilla += sorted(["!" + g for g in gen_h])
				# We're not going to attempt to figure these out.
				continue
			elif isinstance(decl.value, ast.Name):
				# e.g. EXPORTS.gtest += gtest_exports
				# We're not going to attempt to figure these out.
				continue
			elif isinstance(decl.value, ast.List):
				export_list = decl.value
			else:
				#assert False
				pdb.set_trace()

			rel_path = ""
			target = decl.target if isinstance(decl, ast.AugAssign) else decl.targets[0]
			if isinstance(target, ast.Name):
				assert target.id == "EXPORTS"
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

				if li.value[0] == '!':
					# FIXME
					continue

				if rel_path not in to_symlink:
					to_symlink[rel_path] = []

				fullpath = os.path.join(os.path.dirname(filename), li.value)
				to_symlink[rel_path].append(fullpath)
		
	return to_symlink

if __name__ == "__main__":
	parser = argparse.ArgumentParser()
	parser.add_argument("-i", action="store", required=True, help="input mozilla-central directory")
	parser.add_argument("-o", action="store", required=True, help="destination directory for the symlinks")
	args = parser.parse_args()

	for dirpath, dirnames, filenames in os.walk(args.o):
		if len(dirnames) != 0 or len(filenames) != 0:
			print("Output directory is not empty.")
			sys.exit(1)
	
	all_exports = []
	for filepath in get_mozbuild_files(args.i):
		source, root = get_ast(filepath)
		more = get_exports(source, root)
		if len(more):
			all_exports.append((filepath, more))
			
	to_symlink = get_symlink_mapping(all_exports)
	
	for relpath, files in to_symlink.items():
		if relpath:
			try:
				os.makedirs(os.path.join(args.o, relpath))
			except OSError as exc:
			    if exc.errno != errno.EEXIST:
			        raise
			    pass
		print(relpath)
		for f in files:
			src = f
			dst = os.path.join(args.o, relpath, os.path.basename(f))
			print("\t", f)
			try:
				os.symlink(src, dst)
			except:
				print("Could not symlink %s to %s because it already existed." % (src, dst), file=sys.stderr)
	
	# Now do the special icky NSPR stuff
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
				os.symlink(src, dst)
	
	src = os.path.join(args.i, "config/external/nspr/prcpucfg.h")
	dst = os.path.join(args.o, "nspr/prcpucfg.h")
	os.symlink(src, dst)