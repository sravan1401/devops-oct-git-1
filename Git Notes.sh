'''
Git stages ....
> modified 
>> staged 
>>> committed
'''

### Git main stages
'''
> Working Directory
>> Staging Area
>>> .git directory 'Repository'
'''



### Git Config
'''
git config --global user.name "Sravan Jeeru"
git config --global user.email "sravanjeeru@gmail.com"
'''

### Verify config 
'''
git config --list
'''

### Git status
'''
git status (full status)
git status -s (short status)
'''

### Git records
'''
git log
'''

### Git records simplified
'''
git log --all --graph --decorate --oneline
'''
### Git Branch creation
'''
git branch <branch name>
'''

### Git Commiting
'''
git commit -m 'type here the reason'
'''

### Git adding files
'''
git add <filename>
'''

### Git merging
'''
git merge <branch name>
'''

### Git merging without fast-forward mode
'''
git merge --no-ff <branch name>
'''

### Git checkout
'''
git checkout <branch name>
'''

### Git delete branch
'''
git branch -d <branch name>
'''
### signs
'''
??? files not tracked
A - new files added to staging area
M - modified files
'''

### Git ignore
'''
cat .gitignore
*.[oa] - 'ignores all files ending .a and .o'
'''

### to see the changes
'''
git diff 
git diff --staged
'''

### git add directly to repository
'''
git add -a -m <comments> 'skips staging area and goes to repository'
'''

### file remove
'''
rm <filename>
git rm <filename>
'''

### git log
'''
git log -p 'patch file'
git log -p -2 'limit to last 2 entrees'
git log -<n> 'show the last n commits'
git log --since=2.weeks 'lists all commits made in last 2 weeks'
-<n> 'Show only the last n commits'
--since, --after 'Limit the commits to those made after the specified date.'
--until, --before 'Limit the commits to those made before the specified date.'
--author 'Only show commits in which the author entry matches thespecified string.'
--committer 'Only show commits in which the committer entry matches thespecified string.'
--grep 'Only show commits with a commit message containing the string'
-S 'Only show commits adding or removing code matching the string'
git log --author
git log --grep
git log -S
git log --stat 'stats with less info'
git log --pretty=oneline
git log --pretty=format 'see the git formats available over the internet'
'''

### common options to git log
'''
-p 'Show the patch introduced with each commit.'
--stat 'Show statistics for files modified in each commit.'
--shortstat 'Display only the changed/insertions/deletions line from the --stat command.'
--name-only 'Show the list of files modified after the commit information.'
--name-status 'Show the list of files affected with added/modified/deleted information as well.'
--abbrev-commit 'Show only the first few characters of the SHA-1 checksum instead of all 40.'
--relative-date 'Display the date in a relative format (for example, ???2 weeks ago???) instead ofusing the full date format.'
--graph 'Display an ASCII graph of the branch and merge history beside the log output.'
--pretty 'Show commits in an alternate format. Option values include oneline, short,full, fuller, and format (where you specify your own format).'
--oneline 'Shorthand for --pretty=oneline --abbrev-commit used together.'
--no-merges 'displays log output without merge commits'
'''

### example of a search query in git
'''
git log --pretty="%h - %s" --author='Junio C Hamano' --since="2008-10-01" \ --before="2008-11-01" --no-merges -- t/
'''

### to undo/change
'''
git commit --amend
'''

### unstage a file
'''
git restore HEAD <filename>
git restore --staged <filename>
'''

### showing your remotes
'''
git remote
git remote -v 'shows urls that git stored'
'''

### Add remote repository
'''
git remote add <shortname> <url>
'''

### fetch information of the repository
'''
git fetch <shortname>/<origin>
'''

### 