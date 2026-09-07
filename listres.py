import os

def list_resources(rootdir):

    uncategorized = []

    for category in sorted(os.listdir(rootdir)):
        category_path = os.path.join(rootdir, category)

        if not os.path.isdir(category_path):
            continue

        # Kihagyandó kategóriák
        if category == "[tiktok]":
            continue

        # Kategorizált resource-ok
        if category.startswith("["):
            resources = []

            for resource in sorted(os.listdir(category_path)):
                resource_path = os.path.join(category_path, resource)

                if os.path.isdir(resource_path):
                    resources.append(resource)

            if resources:
                print(f"<!-- {category} -->")

                for resource in resources:
                    print(f'<resource src="{resource}" startup="1" protected="0" />')

        # Nem kategorizált resource
        else:
            uncategorized.append(category)

    # Nem kategorizált resource-ok a végén
    if uncategorized:
        print("<!-- Uncategorized -->")

        for resource in uncategorized:
            print(f'<resource src="{resource}" startup="1" protected="0" />')


p = r'C:\Dev\MTASA\server\mods\deathmatch\resources'

list_resources(p)

input("")  # do not close