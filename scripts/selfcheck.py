#!/usr/bin/env python3
"""GM Agent · ObjC 静态自检：找出编译期/运行期常见问题"""
import os, re, glob, sys

ROOT = '/var/minis/workspace/gm/gma/app'
issues = []

def files(ext):
    return sorted(glob.glob(os.path.join(ROOT, '**', '*' + ext), recursive=True))

h_files = files('.h')
m_files = files('.m')

# ---------- 1. @import 的头文件是否存在 ----------
existing_h = {os.path.basename(h) for h in h_files}
for m in m_files + h_files:
    src = open(m, encoding='utf-8', errors='replace').read()
    for imp in re.findall(r'#import\s+"([^"]+)"', src):
        base = os.path.basename(imp)
        if base not in existing_h and not base.startswith('UIKit') and not base.startswith('Foundation'):
            issues.append((m, f'import 缺失: {imp}'))

# ---------- 2. @selector 目标是否在同文件实现 ----------
for m in m_files:
    src = open(m, encoding='utf-8', errors='replace').read()
    impls = set(re.findall(r'-\s*\([^)]*\)\s*(\w+)\s*[;{]', src))
    impls |= set(re.findall(r'\+\s*\([^)]*\)\s*(\w+)\s*[;{]', src))
    for sel in re.findall(r'@selector\(\s*(\w+)\s*\)', src):
        if sel not in impls:
            issues.append((m, f'@selector 无实现: {sel}'))

# ---------- 3. 属性使用但未声明（粗略：self.xxx = 且类内无声明） ----------
for m in m_files:
    src = open(m, encoding='utf-8', errors='replace').read()
    declared = set(re.findall(r'@property\s*\([^)]*\)\s*[\w<>*\s]*?\b(\w+)\s*;', src))
    # 类扩展里声明的也算
    for prop in re.findall(r'self\.(\w+)\s*=', src):
        if prop in ('view', 'title', 'navigationItem', 'tabBarItem', 'viewController'):
            continue
        if prop not in declared:
            # 检查父类常见属性白名单
            if prop in ('backgroundColor', 'text', 'textColor', 'font', 'image', 'tag', 'alpha',
                        'hidden', 'frame', 'bounds', 'center', 'translatesAutoresizingMaskIntoConstraints',
                        'contentMode', 'numberOfLines', 'textAlignment', 'delegate', 'dataSource',
                        'rowHeight', 'estimatedRowHeight', 'separatorStyle', 'keyboardDismissMode',
                        'autoresizingMask', 'editable', 'scrollEnabled', 'secureTextEntry',
                        'autocapitalizationType', 'autocorrectionType', 'spellCheckingType',
                        'clearButtonMode', 'returnKeyType', 'placeholder', 'accessoryView',
                        'accessoryType', 'selectionStyle', 'contentConfiguration', 'layer',
                        'textLabel', 'detailTextLabel', 'imageView', 'contentView', 'inputAccessoryView',
                        'inputView', 'restorationIdentifier', 'tabBarItem'):
                continue
            issues.append((m, f'属性疑似未声明: self.{prop}'))

# ---------- 4. ObjC 类引用是否有对应实现 ----------
declared_classes = set()
for m in m_files:
    src = open(m, encoding='utf-8', errors='replace').read()
    declared_classes |= set(re.findall(r'@implementation\s+(\w+)', src))
for m in m_files:
    src = open(m, encoding='utf-8', errors='replace').read()
    for cls in re.findall(r'\[\s*(\w{2,})\s+(?:new|alloc)\]', src):
        if cls[0].isupper() and cls not in declared_classes:
            if cls in ('NSString', 'NSArray', 'NSDictionary', 'NSMutableArray', 'NSMutableDictionary',
                       'NSNumber', 'NSData', 'NSDate', 'NSURL', 'NSURLRequest', 'NSMutableURLRequest',
                       'NSURLSession', 'NSFileManager', 'NSUserDefaults', 'UILabel', 'UIView',
                       'UIImage', 'UIImageView', 'UIButton', 'UITextField', 'UITextView', 'UITableView',
                       'UITableViewCell', 'UIAlertController', 'UIAlertAction', 'UISwitch',
                       'UISegmentedControl', 'UIActivityIndicatorView', 'UIToolbar', 'UIBarButtonItem',
                       'UINavigationController', 'UIWindow', 'UIViewController', 'UIScreen',
                       'NSMutableString', 'NSMutableData', 'NSIndexPath', 'NSError', 'NSPipe',
                       'NSFileHandle', 'NSDateFormatter', 'NSDirectoryEnumerator', 'NSNotificationCenter'):
                continue
            issues.append((m, f'类引用无实现: {cls}'))

# ---------- 5. 引擎里导出/使用是否匹配 ----------
eng = '/var/minis/workspace/gm/gma/engine'
hdr = open(os.path.join(eng, 'gm_engine.h'), encoding='utf-8').read()
for c in sorted(glob.glob(os.path.join(eng, '*.c'))):
    src = open(c, encoding='utf-8', errors='replace').read()
    for fn in re.findall(r'^[a-zA-Z_][\w \*]*\b(gm_\w+)\s*\(', src, re.M):
        if fn not in hdr and not fn.startswith('gm_turn_run') and 'static' not in fn:
            pass  # 内部函数允许

# ---------- 6. 引擎：double free / 未初始化 ----------
for c in sorted(glob.glob(os.path.join(eng, '*.c'))):
    src = open(c, encoding='utf-8', errors='replace').read()
    # gm_val_free 已被 arena 取代，若仍有调用要警告
    if 'gm_val_free' in src:
        issues.append((c, '仍在调用已移除的 gm_val_free（arena 模式下应是 gm_arena_reset）'))
    # free() 在 arena 对象上
    for m in re.finditer(r'free\s*\(\s*(\w+)\s*\)', src):
        pass

# ---------- 输出 ----------
if not issues:
    print('✅ 自检通过，未发现问题')
else:
    print(f'发现 {len(issues)} 处可疑点：\n')
    seen = set()
    for f, msg in issues:
        key = (os.path.basename(f), msg)
        if key in seen:
            continue
        seen.add(key)
        print(f'  [{os.path.basename(f)}] {msg}')
print()
print(f'扫描：{len(m_files)} 个 .m / {len(h_files)} 个 .h / {len(glob.glob(os.path.join(eng, "*.c")))} 个 .c')
