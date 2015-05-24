from django.shortcuts import render,redirect
from .forms import CommentForm
from .models import Comment

def add_comment(request):
	if request.method == "POST":
		form = CommentForm(request.POST)
		if form.is_valid():
			comment = form.save(commit=False)
			comment.save()
			return redirect('comment.views.home',)
	else:
		form = CommentForm()
	return render(request, 'comment/add_comment.html', {'form': form})

def home(request):
	Comments= Comment.objects.order_by('-id')
	return render(request,'comment/comment.html',{'comments':Comments})